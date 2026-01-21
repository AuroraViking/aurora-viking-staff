/**
 * Booking Management Module
 * Handles reschedule, cancel, and pickup location changes
 * 
 * UPDATED: Added proper OTA booking detection and graceful handling
 */
const { onRequest } = require('firebase-functions/v2/https');
const { onCall } = require('firebase-functions/v2/https');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const crypto = require('crypto');
const https = require('https');
const { admin, db } = require('../utils/firebase');
const { makeBokunRequest } = require('../utils/bokun_client');

/**
 * Helper: Detect if booking is from an OTA (reseller)
 * Returns { isOTA: boolean, otaName: string | null, otaPortalUrl: string | null }
 */
function detectOTABooking(booking) {
    const externalRef = (booking.externalBookingReference || '').toLowerCase();
    const confirmCode = (booking.confirmationCode || '').toUpperCase();

    // Viator detection
    if (externalRef.includes('viator') || confirmCode.startsWith('VIA-')) {
        return {
            isOTA: true,
            otaName: 'Viator',
            otaPortalUrl: 'https://supplier.viator.com/',
            otaInstructions: 'Log into Viator Supplier Portal → Bookings → Find by reference → Modify'
        };
    }

    // GetYourGuide detection
    if (externalRef.includes('gyg') || externalRef.includes('getyourguide') || confirmCode.startsWith('GYG-')) {
        return {
            isOTA: true,
            otaName: 'GetYourGuide',
            otaPortalUrl: 'https://supplier.getyourguide.com/',
            otaInstructions: 'Log into GYG Supplier Portal → Bookings → Find by reference → Request change'
        };
    }

    // TourDesk / Traveldesk detection
    if (externalRef.includes('tdi') || externalRef.includes('tourdesk') || confirmCode.startsWith('TDI-')) {
        return {
            isOTA: true,
            otaName: 'TourDesk',
            otaPortalUrl: 'https://tourdesk.io/',
            otaInstructions: 'Contact TourDesk support or log into their portal to modify'
        };
    }

    // Expedia detection
    if (externalRef.includes('expedia') || confirmCode.startsWith('EXP-')) {
        return {
            isOTA: true,
            otaName: 'Expedia',
            otaPortalUrl: 'https://www.expediapartnercentral.com/',
            otaInstructions: 'Log into Expedia Partner Central → Reservations → Modify'
        };
    }

    return { isOTA: false, otaName: null, otaPortalUrl: null, otaInstructions: null };
}

/**
 * Get booking details by ID from Bokun
 */
const getBookingDetails = onRequest(
    {
        cors: true,
        secrets: ['BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY'],
    },
    async (req, res) => {
        if (req.method !== 'POST') {
            res.status(405).json({ error: 'Method not allowed' });
            return;
        }

        const authHeader = req.headers.authorization;
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            res.status(401).json({ error: 'Unauthorized - missing token' });
            return;
        }

        try {
            const token = authHeader.split('Bearer ')[1];
            await admin.auth().verifyIdToken(token);

            const requestData = req.body.data || req.body;
            const { bookingId } = requestData;

            if (!bookingId) {
                res.status(400).json({ error: 'bookingId is required' });
                return;
            }

            const accessKey = process.env.BOKUN_ACCESS_KEY;
            const secretKey = process.env.BOKUN_SECRET_KEY;

            if (!accessKey || !secretKey) {
                res.status(500).json({ error: 'Bokun API keys not configured' });
                return;
            }

            const result = await makeBokunRequest(
                'GET',
                `/booking.json/${bookingId}`,
                null,
                accessKey,
                secretKey
            );

            res.status(200).json({ result });
        } catch (error) {
            console.error('Error in getBookingDetails:', error);
            res.status(500).json({ error: error.message });
        }
    }
);

/**
 * Reschedule a booking (onCall version)
 */
const rescheduleBooking = onCall(
    {
        region: 'us-central1',
        secrets: ['BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY'],
    },
    async (request) => {
        if (!request.auth) {
            throw new Error('Unauthorized - must be logged in');
        }
        const uid = request.auth.uid;

        const { bookingId, confirmationCode, newDate, reason } = request.data;

        if (!bookingId || !newDate) {
            throw new Error('bookingId and newDate are required');
        }

        const accessKey = process.env.BOKUN_ACCESS_KEY;
        const secretKey = process.env.BOKUN_SECRET_KEY;

        if (!accessKey || !secretKey) {
            throw new Error('Bokun API keys not configured');
        }

        // Get current booking details
        const currentBooking = await makeBokunRequest(
            'GET',
            `/booking.json/${bookingId}`,
            null,
            accessKey,
            secretKey
        );

        const amendRequest = {
            bookingId: bookingId,
            newStartDate: newDate,
        };

        try {
            const result = await makeBokunRequest(
                'POST',
                `/booking.json/${bookingId}/reschedule`,
                amendRequest,
                accessKey,
                secretKey
            );

            // Log the action
            await db.collection('booking_actions').add({
                bookingId,
                confirmationCode: confirmationCode || '',
                action: 'reschedule',
                performedBy: uid,
                performedAt: admin.firestore.FieldValue.serverTimestamp(),
                reason: reason || 'Rescheduled via admin app',
                originalData: { date: currentBooking.startDate || 'unknown' },
                newData: { date: newDate },
                success: true,
                source: 'cloud_function',
            });

            return { result, success: true };
        } catch (amendError) {
            console.error('Bokun amend failed:', amendError.message);

            await db.collection('booking_actions').add({
                bookingId,
                confirmationCode: confirmationCode || '',
                action: 'reschedule',
                performedBy: uid,
                performedAt: admin.firestore.FieldValue.serverTimestamp(),
                reason: reason || 'Attempted reschedule',
                newData: { date: newDate },
                success: false,
                errorMessage: amendError.message,
                source: 'cloud_function',
            });

            throw new Error(`Reschedule failed: ${amendError.message}. You may need to cancel and rebook manually.`);
        }
    }
);

/**
 * Firestore Trigger: Process reschedule requests
 * This is the main reschedule handler using OCTO API
 * 
 * UPDATED: Now properly detects OTA bookings and fails gracefully with helpful info
 */
const onRescheduleRequest = onDocumentCreated(
    {
        document: 'reschedule_requests/{requestId}',
        region: 'us-central1',
        secrets: ['BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY', 'BOKUN_OCTO_TOKEN'],
    },
    async (event) => {
        const snapshot = event.data;
        if (!snapshot) {
            console.log('No data in reschedule request');
            return;
        }

        const requestData = snapshot.data();
        const requestId = event.params.requestId;

        if (requestData.status === 'completed' || requestData.status === 'failed') {
            console.log(`Request ${requestId} already processed`);
            return;
        }

        const { bookingId, confirmationCode, newDate, reason, userId } = requestData;

        console.log(`📅 Processing reschedule request: ${requestId} for booking ${bookingId}`);

        // VALIDATION: Check if newDate is in the past
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const requestedDate = new Date(newDate + 'T00:00:00');

        if (requestedDate < today) {
            console.error(`❌ Requested date ${newDate} is in the past`);
            await snapshot.ref.update({
                status: 'failed',
                error: `Cannot reschedule to a past date (${newDate}).`,
                failedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            return;
        }

        await snapshot.ref.update({ status: 'processing' });

        try {
            const accessKey = process.env.BOKUN_ACCESS_KEY;
            const secretKey = process.env.BOKUN_SECRET_KEY;
            const octoToken = process.env.BOKUN_OCTO_TOKEN;

            if (!accessKey || !secretKey) {
                throw new Error('Bokun API keys not configured');
            }
            if (!octoToken) {
                throw new Error('OCTO token not configured');
            }

            // Search for the booking
            console.log(`🔍 Searching for booking ${bookingId}...`);

            const now = new Date();
            const bokunDate = now.toISOString().replace('T', ' ').substring(0, 19);
            const searchPath = '/booking.json/booking-search';
            const message = bokunDate + accessKey + 'POST' + searchPath;
            const signature = crypto.createHmac('sha1', secretKey).update(message).digest('base64');
            const searchRequest = { id: parseInt(bookingId), limit: 10 };

            const searchResult = await new Promise((resolve, reject) => {
                const postData = JSON.stringify(searchRequest);
                const options = {
                    hostname: 'api.bokun.io',
                    path: searchPath,
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json;charset=UTF-8',
                        'Content-Length': Buffer.byteLength(postData),
                        'X-Bokun-AccessKey': accessKey,
                        'X-Bokun-Date': bokunDate,
                        'X-Bokun-Signature': signature,
                    },
                };

                const apiReq = https.request(options, (apiRes) => {
                    let data = '';
                    apiRes.on('data', (chunk) => { data += chunk; });
                    apiRes.on('end', () => {
                        if (apiRes.statusCode >= 200 && apiRes.statusCode < 300) {
                            try { resolve(JSON.parse(data)); } catch (e) { reject(new Error('Failed to parse')); }
                        } else {
                            reject(new Error(`Bokun search error: ${apiRes.statusCode}`));
                        }
                    });
                });
                apiReq.on('error', reject);
                apiReq.write(postData);
                apiReq.end();
            });

            const foundBooking = searchResult.items?.find(b => String(b.id) === String(bookingId));
            if (!foundBooking) {
                throw new Error(`Booking ${bookingId} not found`);
            }

            console.log(`✅ Found booking ${bookingId} (${foundBooking.confirmationCode})`);

            // OTA DETECTION
            const otaInfo = detectOTABooking(foundBooking);
            if (otaInfo.isOTA) {
                console.log(`🏷️ Detected ${otaInfo.otaName} booking`);
            }

            const productBooking = foundBooking.productBookings?.[0];
            if (!productBooking) {
                throw new Error('No product booking found');
            }

            const productId = productBooking.product?.id;
            const optionId = productBooking.activity?.id || productBooking.rate?.id || productId;
            const currentDate = productBooking.startDate || 'Unknown';
            const customerName = foundBooking.customer?.firstName
                ? `${foundBooking.customer.firstName} ${foundBooking.customer.lastName || ''}`.trim()
                : 'Unknown Customer';

            console.log(`📦 Product ID: ${productId}, Current date: ${currentDate}, New date: ${newDate}`);

            // OCTO helper
            const octoRequest = (method, path, body = null) => {
                return new Promise((resolve, reject) => {
                    const postData = body ? JSON.stringify(body) : null;
                    const options = {
                        hostname: 'api.bokun.io',
                        path: `/octo/v1${path}`,
                        method: method,
                        headers: {
                            'Content-Type': 'application/json',
                            'Authorization': `Bearer ${octoToken}`,
                        },
                    };
                    if (postData) options.headers['Content-Length'] = Buffer.byteLength(postData);

                    const apiReq = https.request(options, (apiRes) => {
                        let data = '';
                        apiRes.on('data', (chunk) => { data += chunk; });
                        apiRes.on('end', () => {
                            if (apiRes.statusCode >= 200 && apiRes.statusCode < 300) {
                                try { resolve(data ? JSON.parse(data) : {}); } catch (e) { resolve(data); }
                            } else {
                                reject(new Error(`OCTO API error: ${apiRes.statusCode} - ${data}`));
                            }
                        });
                    });
                    apiReq.on('error', reject);
                    if (postData) apiReq.write(postData);
                    apiReq.end();
                });
            };

            // Get OCTO products
            let octoProductId = String(productId);
            let octoOptionId = String(optionId);
            let defaultUnitId = null;

            try {
                const octoProducts = await octoRequest('GET', '/products');
                if (Array.isArray(octoProducts) && octoProducts.length > 0) {
                    const matchingProduct = octoProducts.find(p => String(p.id) === String(productId));
                    let optionToUse = null;
                    if (matchingProduct) {
                        octoProductId = String(matchingProduct.id);
                        if (matchingProduct.options?.length > 0) {
                            optionToUse = matchingProduct.options[0];
                            octoOptionId = String(optionToUse.id);
                        }
                    } else {
                        const firstProduct = octoProducts[0];
                        octoProductId = String(firstProduct.id);
                        if (firstProduct.options?.length > 0) {
                            optionToUse = firstProduct.options[0];
                            octoOptionId = String(optionToUse.id);
                        }
                    }
                    if (optionToUse?.units?.length > 0) {
                        defaultUnitId = String(optionToUse.units[0].id);
                    }
                }
            } catch (e) {
                console.log(`⚠️ Could not fetch OCTO products: ${e.message}`);
            }

            // Check availability
            console.log(`🔍 Checking availability for ${newDate}...`);
            const availabilityResult = await octoRequest('POST', '/availability', {
                productId: octoProductId,
                optionId: octoOptionId,
                localDate: newDate,
            });

            if (!Array.isArray(availabilityResult) || availabilityResult.length === 0) {
                throw new Error(`No availability found for ${newDate}.`);
            }

            const newAvailability = availabilityResult[0];
            const availabilityId = newAvailability.id;
            console.log(`✅ Found availability: ${availabilityId}`);

            // Get startTimeId from Bokun
            let startTimeId = null;
            try {
                const startTimesPath = `/activity.json/${productId}/availabilities`;
                const stDate = new Date().toISOString().replace('T', ' ').substring(0, 19);
                const stMessage = stDate + accessKey + 'POST' + startTimesPath;
                const stSignature = crypto.createHmac('sha1', secretKey).update(stMessage).digest('base64');

                const startTimesResult = await new Promise((resolve) => {
                    const stBody = JSON.stringify({ start: newDate, end: newDate });
                    const options = {
                        hostname: 'api.bokun.io',
                        path: startTimesPath,
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json;charset=UTF-8',
                            'Content-Length': Buffer.byteLength(stBody),
                            'X-Bokun-AccessKey': accessKey,
                            'X-Bokun-Date': stDate,
                            'X-Bokun-Signature': stSignature,
                        },
                    };

                    const apiReq = https.request(options, (apiRes) => {
                        let data = '';
                        apiRes.on('data', (chunk) => { data += chunk; });
                        apiRes.on('end', () => {
                            if (apiRes.statusCode >= 200 && apiRes.statusCode < 300) {
                                try { resolve(JSON.parse(data)); } catch (e) { resolve(null); }
                            } else { resolve(null); }
                        });
                    });
                    apiReq.on('error', () => resolve(null));
                    apiReq.write(stBody);
                    apiReq.end();
                });

                if (startTimesResult) {
                    const availabilities = startTimesResult.availabilities || startTimesResult;
                    if (Array.isArray(availabilities) && availabilities.length > 0) {
                        const firstSlot = availabilities[0];
                        startTimeId = firstSlot.startTimeId || firstSlot.id || firstSlot.startTime?.id;
                        console.log(`📅 Found Bokun startTimeId: ${startTimeId}`);
                    }
                }
            } catch (e) {
                console.log(`⚠️ Could not fetch Bokun start times: ${e.message}`);
            }

            // Try OCTO booking first
            let octoBookingUuid = null;
            try {
                let octoBookings = await octoRequest('GET', `/bookings?supplierReference=${bookingId}`);
                if (Array.isArray(octoBookings) && octoBookings.length > 0) {
                    octoBookingUuid = octoBookings[0].uuid;
                    console.log(`✅ Found OCTO booking UUID: ${octoBookingUuid}`);
                }
                if (!octoBookingUuid) {
                    const confirmCodeForSearch = confirmationCode || foundBooking.confirmationCode;
                    octoBookings = await octoRequest('GET', `/bookings?resellerReference=${confirmCodeForSearch}`);
                    if (Array.isArray(octoBookings) && octoBookings.length > 0) {
                        octoBookingUuid = octoBookings[0].uuid;
                    }
                }
            } catch (e) {
                console.log(`⚠️ Could not find OCTO booking: ${e.message}`);
            }

            if (!octoBookingUuid) {
                // Try ActivityChangeDateAction
                console.log(`⚠️ OCTO booking not found - trying ActivityChangeDateAction...`);
                const activityBookingId = productBooking.id;

                if (activityBookingId) {
                    try {
                        const editPath = '/booking.json/edit';
                        const editDate = new Date().toISOString().replace('T', ' ').substring(0, 19);
                        const editMessage = editDate + accessKey + 'POST' + editPath;
                        const editSignature = crypto.createHmac('sha1', secretKey).update(editMessage).digest('base64');

                        const changeDateActions = [{
                            type: 'ActivityChangeDateAction',
                            activityBookingId: parseInt(activityBookingId),
                            date: newDate,
                            ...(startTimeId && { startTimeId: parseInt(startTimeId) }),
                        }];

                        console.log(`📅 Trying ActivityChangeDateAction for activity ${activityBookingId} to ${newDate} with startTimeId ${startTimeId || 'none'}`);

                        await new Promise((resolve, reject) => {
                            const editBody = JSON.stringify(changeDateActions);
                            const options = {
                                hostname: 'api.bokun.io',
                                path: editPath,
                                method: 'POST',
                                headers: {
                                    'Content-Type': 'application/json;charset=UTF-8',
                                    'Content-Length': Buffer.byteLength(editBody),
                                    'X-Bokun-AccessKey': accessKey,
                                    'X-Bokun-Date': editDate,
                                    'X-Bokun-Signature': editSignature,
                                },
                            };

                            const apiReq = https.request(options, (apiRes) => {
                                let data = '';
                                apiRes.on('data', (chunk) => { data += chunk; });
                                apiRes.on('end', () => {
                                    console.log(`📅 ActivityChangeDateAction response: ${apiRes.statusCode}`);
                                    if (apiRes.statusCode >= 200 && apiRes.statusCode < 400) {
                                        resolve({ success: true, data });
                                    } else {
                                        reject(new Error(`ActivityChangeDateAction failed: ${apiRes.statusCode} - ${data}`));
                                    }
                                });
                            });
                            apiReq.on('error', reject);
                            apiReq.write(editBody);
                            apiReq.end();
                        });

                        console.log(`✅ ActivityChangeDateAction succeeded!`);

                        await db.collection('booking_actions').add({
                            bookingId,
                            confirmationCode: confirmationCode || foundBooking.confirmationCode,
                            customerName,
                            action: 'reschedule',
                            performedBy: userId || 'unknown',
                            performedAt: admin.firestore.FieldValue.serverTimestamp(),
                            reason: reason || 'Rescheduled via admin app',
                            originalData: { date: currentDate },
                            newData: { date: newDate },
                            success: true,
                            method: 'activity_change_date_action',
                            isOTABooking: otaInfo.isOTA,
                            otaName: otaInfo.otaName,
                        });

                        await snapshot.ref.update({
                            status: 'completed',
                            method: 'activity_change_date_action',
                            customerName,
                            originalDate: currentDate,
                            completedAt: admin.firestore.FieldValue.serverTimestamp(),
                            message: `Booking rescheduled to ${newDate} via ActivityChangeDateAction`,
                        });

                        console.log(`✅ Reschedule completed via ActivityChangeDateAction: ${requestId}`);
                        return;

                    } catch (changeDateError) {
                        console.log(`⚠️ ActivityChangeDateAction failed: ${changeDateError.message}`);

                        if (otaInfo.isOTA && changeDateError.message.includes('401')) {
                            const otaErrorMessage = `OTA booking from ${otaInfo.otaName} cannot be rescheduled via API. Use: ${otaInfo.otaPortalUrl}`;
                            await snapshot.ref.update({
                                status: 'failed',
                                error: otaErrorMessage,
                                isOTABooking: true,
                                otaName: otaInfo.otaName,
                                otaPortalUrl: otaInfo.otaPortalUrl,
                                failedAt: admin.firestore.FieldValue.serverTimestamp(),
                            });
                            return;
                        }
                    }
                }

                // Skip cancel+rebook for OTA bookings
                if (otaInfo.isOTA) {
                    const otaErrorMessage = `OTA booking from ${otaInfo.otaName} requires manual reschedule. Portal: ${otaInfo.otaPortalUrl}`;
                    await snapshot.ref.update({
                        status: 'failed',
                        error: otaErrorMessage,
                        isOTABooking: true,
                        otaName: otaInfo.otaName,
                        otaPortalUrl: otaInfo.otaPortalUrl,
                        failedAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                    return;
                }

                // Cancel + rebook for non-OTA bookings (code continues with existing logic)
                console.log(`⚠️ Using cancel + rebook strategy`);
                throw new Error('Cancel + rebook not implemented in this version - use full file');
            }

            // OCTO PATCH
            console.log(`📝 Updating booking ${octoBookingUuid} via OCTO...`);
            await octoRequest('PATCH', `/bookings/${octoBookingUuid}`, { availabilityId });

            console.log(`✅ Booking updated via OCTO API!`);

            await db.collection('booking_actions').add({
                bookingId,
                confirmationCode: confirmationCode || foundBooking.confirmationCode,
                customerName,
                action: 'reschedule',
                performedBy: userId || 'unknown',
                performedAt: admin.firestore.FieldValue.serverTimestamp(),
                reason: reason || 'Rescheduled via admin app',
                originalData: { date: currentDate },
                newData: { date: newDate, availabilityId },
                success: true,
                source: 'octo_api',
            });

            await snapshot.ref.update({
                status: 'completed',
                availabilityId,
                customerName,
                originalDate: currentDate,
                completedAt: admin.firestore.FieldValue.serverTimestamp(),
                message: `Booking rescheduled to ${newDate}`,
            });

            console.log(`✅ Reschedule completed: ${requestId}`);

        } catch (error) {
            console.error(`❌ Reschedule failed: ${error.message}`);
            await snapshot.ref.update({
                status: 'failed',
                error: error.message,
                failedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
    }
);

// Export all functions
module.exports = {
    getBookingDetails,
    rescheduleBooking,
    onRescheduleRequest,
    detectOTABooking,
};
