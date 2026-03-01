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
            // For OTA bookings (GetYourGuide, Viator), the bookingId from the AI cache may be wrong
            // So we try multiple search strategies
            console.log(`🔍 Searching for booking ${bookingId} (confirmationCode: ${confirmationCode})...`);

            const now = new Date();
            const bokunDate = now.toISOString().replace('T', ' ').substring(0, 19);
            const searchPath = '/booking.json/booking-search';
            const message = bokunDate + accessKey + 'POST' + searchPath;
            const signature = crypto.createHmac('sha1', secretKey).update(message).digest('base64');

            // Try searching by confirmation code first (more reliable for OTA bookings)
            let searchRequest;
            if (confirmationCode) {
                searchRequest = { confirmationCode: confirmationCode, limit: 10 };
            } else {
                searchRequest = { id: parseInt(bookingId), limit: 10 };
            }

            let searchResult = await new Promise((resolve, reject) => {
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

            // Try to find by confirmation code match
            let foundBooking = searchResult.items?.find(b =>
                String(b.confirmationCode) === String(confirmationCode) ||
                String(b.id) === String(bookingId)
            );

            // If not found by confirmation code, try searching by ID as fallback
            if (!foundBooking && confirmationCode) {
                console.log(`⚠️ No match by confirmation code, trying by ID ${bookingId}...`);

                const fallbackBokunDate = new Date().toISOString().replace('T', ' ').substring(0, 19);
                const fallbackMessage = fallbackBokunDate + accessKey + 'POST' + searchPath;
                const fallbackSignature = crypto.createHmac('sha1', secretKey).update(fallbackMessage).digest('base64');

                searchResult = await new Promise((resolve, reject) => {
                    const postData = JSON.stringify({ id: parseInt(bookingId), limit: 10 });
                    const options = {
                        hostname: 'api.bokun.io',
                        path: searchPath,
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json;charset=UTF-8',
                            'Content-Length': Buffer.byteLength(postData),
                            'X-Bokun-AccessKey': accessKey,
                            'X-Bokun-Date': fallbackBokunDate,
                            'X-Bokun-Signature': fallbackSignature,
                        },
                    };

                    const apiReq = https.request(options, (apiRes) => {
                        let data = '';
                        apiRes.on('data', (chunk) => { data += chunk; });
                        apiRes.on('end', () => {
                            if (apiRes.statusCode >= 200 && apiRes.statusCode < 300) {
                                try { resolve(JSON.parse(data)); } catch (e) { resolve({ items: [] }); }
                            } else {
                                resolve({ items: [] });
                            }
                        });
                    });
                    apiReq.on('error', () => resolve({ items: [] }));
                    apiReq.write(postData);
                    apiReq.end();
                });

                foundBooking = searchResult.items?.find(b => String(b.id) === String(bookingId));
            }

            if (!foundBooking) {
                throw new Error(`Booking ${bookingId} (${confirmationCode}) not found`);
            }

            console.log(`✅ Found booking ${foundBooking.id} (${foundBooking.confirmationCode})`);

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

                // Cancel + rebook for non-OTA bookings
                // IMPORTANT: Create the new booking FIRST, then cancel the original
                // This way if rebook fails, the customer still has their original booking
                console.log(`⚠️ Using cancel + rebook strategy for booking ${bookingId}...`);

                try {
                    const cancelConfCode = confirmationCode || foundBooking.confirmationCode;
                    if (!cancelConfCode) {
                        throw new Error('No confirmation code available for cancellation');
                    }

                    // Step 1: Create new booking via OCTO on the new date FIRST
                    console.log(`📝 Creating new booking on ${newDate} via OCTO...`);

                    // Get unit counts from original booking
                    const originalUnits = [];
                    const participants = productBooking.participants || productBooking.fields?.participants || [];
                    if (participants.length > 0) {
                        const unitCounts = {};
                        for (const p of participants) {
                            const unitId = p.unitId || p.category || defaultUnitId || 'default';
                            unitCounts[unitId] = (unitCounts[unitId] || 0) + 1;
                        }
                        for (const [unitId, qty] of Object.entries(unitCounts)) {
                            originalUnits.push({ id: String(unitId), quantity: qty });
                        }
                    }

                    // Fallback: if no participants found, use totalParticipants count
                    if (originalUnits.length === 0) {
                        const totalParticipants = productBooking.totalParticipants ||
                            foundBooking.totalParticipants ||
                            productBooking.participants?.length || 1;
                        const unitId = defaultUnitId || 'default';
                        originalUnits.push({ id: String(unitId), quantity: totalParticipants });
                    }

                    console.log(`👥 Units for new booking: ${JSON.stringify(originalUnits)}`);

                    // Reserve via OCTO
                    const reserveBody = {
                        productId: octoProductId,
                        optionId: octoOptionId,
                        availabilityId: newAvailability.id,
                        unitItems: originalUnits.flatMap(u =>
                            Array.from({ length: u.quantity }, () => ({ unitId: u.id }))
                        ),
                    };

                    const reservation = await octoRequest('POST', '/bookings', reserveBody);
                    console.log(`✅ OCTO reservation created: ${reservation.uuid}`);

                    // Confirm the OCTO booking with customer details
                    // OCTO confirm only accepts: contact, resellerReference, emailReceipt, unitItems
                    const confirmBody = {
                        contact: {
                            firstName: foundBooking.customer?.firstName || '',
                            lastName: foundBooking.customer?.lastName || '',
                            emailAddress: foundBooking.customer?.email || '',
                            phoneNumber: foundBooking.customer?.phoneNumber || foundBooking.customer?.phone || '',
                        },
                        resellerReference: cancelConfCode,
                    };

                    const confirmedBooking = await octoRequest('POST', `/bookings/${reservation.uuid}/confirm`, confirmBody);
                    console.log(`✅ New booking confirmed: ${confirmedBooking.uuid}`);

                    const newBookingId = confirmedBooking.supplierReference || confirmedBooking.uuid;

                    // Step 2: NOW cancel the original booking (safe since new one exists)
                    console.log(`🗑️ Cancelling original booking ${cancelConfCode}...`);
                    try {
                        await makeBokunRequest(
                            'POST',
                            `/booking.json/cancel-booking/${cancelConfCode}`,
                            { note: `Rescheduled to ${newDate}. New booking: ${newBookingId}`, notify: false },
                            accessKey,
                            secretKey
                        );
                        console.log(`✅ Original booking cancelled`);
                    } catch (cancelError) {
                        // New booking exists but old one couldn't be cancelled
                        // Still mark as success but note the issue
                        console.warn(`⚠️ Could not cancel original booking: ${cancelError.message}`);
                    }

                    // Log the action
                    await db.collection('booking_actions').add({
                        bookingId,
                        newBookingId,
                        confirmationCode: cancelConfCode,
                        customerName,
                        action: 'reschedule',
                        performedBy: userId || 'unknown',
                        performedAt: admin.firestore.FieldValue.serverTimestamp(),
                        reason: reason || 'Rescheduled via admin app',
                        originalData: { date: currentDate },
                        newData: { date: newDate, newBookingId },
                        success: true,
                        method: 'cancel_and_rebook',
                        isOTABooking: false,
                    });

                    await snapshot.ref.update({
                        status: 'completed',
                        method: 'cancel_and_rebook',
                        customerName,
                        originalDate: currentDate,
                        newBookingId,
                        completedAt: admin.firestore.FieldValue.serverTimestamp(),
                        message: `Booking rescheduled to ${newDate} (cancel + rebook). New booking: ${newBookingId}`,
                    });

                    console.log(`✅ Reschedule completed via cancel+rebook: ${requestId}`);
                    return;

                } catch (cancelRebookError) {
                    console.error(`❌ Cancel+rebook failed: ${cancelRebookError.message}`);

                    // Since we create the new booking FIRST, if we get here the original is untouched
                    const portalLink = `https://bokun.io/operations/bookings/${bookingId}`;
                    await snapshot.ref.update({
                        status: 'completed',
                        requiresManualAction: true,
                        bokunPortalLink: portalLink,
                        customerName,
                        originalDate: currentDate,
                        availabilityConfirmed: true,
                        availabilityId: newAvailability?.id || null,
                        completedAt: admin.firestore.FieldValue.serverTimestamp(),
                        message: `Automatic reschedule failed (${cancelRebookError.message}). Original booking is unchanged. Please reschedule manually in Bokun.`,
                    });
                    return;
                }
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

/**
 * Get pickup places for an activity/product
 */
const getPickupPlaces = onRequest(
    {
        cors: true,
        invoker: 'public',
        secrets: ['BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY'],
    },
    async (req, res) => {
        if (req.method !== 'GET' && req.method !== 'POST') {
            res.status(405).json({ error: 'Method not allowed' });
            return;
        }

        const authHeader = req.headers.authorization;
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            res.status(401).json({ error: 'Unauthorized' });
            return;
        }

        try {
            const idToken = authHeader.split('Bearer ')[1];
            await admin.auth().verifyIdToken(idToken);
        } catch (error) {
            res.status(401).json({ error: 'Invalid token' });
            return;
        }

        const productId = req.query.productId || req.body.productId;
        if (!productId) {
            res.status(400).json({ error: 'productId is required' });
            return;
        }

        const accessKey = process.env.BOKUN_ACCESS_KEY;
        const secretKey = process.env.BOKUN_SECRET_KEY;

        if (!accessKey || !secretKey) {
            res.status(500).json({ error: 'Bokun API keys not configured' });
            return;
        }

        try {
            console.log(`📍 Fetching pickup places for product ${productId}`);

            const pickupPath = `/activity.json/${productId}/pickup-places`;
            const pickupDate = new Date().toISOString().replace('T', ' ').substring(0, 19);
            const pickupMessage = pickupDate + accessKey + 'GET' + pickupPath;
            const pickupSignature = crypto.createHmac('sha1', secretKey).update(pickupMessage).digest('base64');

            const pickupPlaces = await new Promise((resolve) => {
                const options = {
                    hostname: 'api.bokun.io',
                    path: pickupPath,
                    method: 'GET',
                    headers: {
                        'X-Bokun-AccessKey': accessKey,
                        'X-Bokun-Date': pickupDate,
                        'X-Bokun-Signature': pickupSignature,
                    },
                };

                const apiReq = https.request(options, (apiRes) => {
                    let data = '';
                    apiRes.on('data', (chunk) => { data += chunk; });
                    apiRes.on('end', () => {
                        if (apiRes.statusCode >= 200 && apiRes.statusCode < 300) {
                            try {
                                const parsed = JSON.parse(data);
                                resolve(parsed.pickupPlaces || parsed.pickupDropoffPlaces || parsed.items || parsed);
                            } catch (e) { resolve([]); }
                        } else { resolve([]); }
                    });
                });
                apiReq.on('error', () => resolve([]));
                apiReq.end();
            });

            const places = (Array.isArray(pickupPlaces) ? pickupPlaces : []).map(place => ({
                id: place.id,
                title: place.title || place.name,
                address: place.address?.streetAddress || place.address || '',
                city: place.address?.city || '',
                type: place.type || 'HOTEL',
            }));

            console.log(`✅ Found ${places.length} pickup places`);
            res.json({ pickupPlaces: places });

        } catch (error) {
            console.error(`❌ Error fetching pickup places: ${error.message}`);
            res.status(500).json({ error: error.message });
        }
    }
);

/**
 * Update pickup location on an existing booking
 */
const updatePickupLocation = onRequest(
    {
        cors: true,
        invoker: 'public',
        secrets: ['BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY'],
    },
    async (req, res) => {
        if (req.method !== 'POST') {
            res.status(405).json({ error: 'Method not allowed' });
            return;
        }

        const authHeader = req.headers.authorization;
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            res.status(401).json({ error: 'Unauthorized' });
            return;
        }

        try {
            const idToken = authHeader.split('Bearer ')[1];
            await admin.auth().verifyIdToken(idToken);
        } catch (error) {
            res.status(401).json({ error: 'Invalid token' });
            return;
        }

        const { bookingId, productBookingId, pickupPlaceId, pickupPlaceName } = req.body;

        if (!bookingId || !pickupPlaceId) {
            res.status(400).json({ error: 'bookingId and pickupPlaceId are required' });
            return;
        }

        const accessKey = process.env.BOKUN_ACCESS_KEY;
        const secretKey = process.env.BOKUN_SECRET_KEY;

        if (!accessKey || !secretKey) {
            res.status(500).json({ error: 'Bokun API keys not configured' });
            return;
        }

        try {
            console.log(`📍 Updating pickup for booking ${bookingId} to place ${pickupPlaceId}`);

            let actualProductBookingId = productBookingId;

            if (!actualProductBookingId) {
                const searchPath = '/booking.json/booking-search';
                const searchDate = new Date().toISOString().replace('T', ' ').substring(0, 19);
                const searchMessage = searchDate + accessKey + 'POST' + searchPath;
                const searchSignature = crypto.createHmac('sha1', secretKey).update(searchMessage).digest('base64');

                const searchResult = await new Promise((resolve, reject) => {
                    const searchBody = JSON.stringify({ bookingId: parseInt(bookingId) });
                    const options = {
                        hostname: 'api.bokun.io',
                        path: searchPath,
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json;charset=UTF-8',
                            'Content-Length': Buffer.byteLength(searchBody),
                            'X-Bokun-AccessKey': accessKey,
                            'X-Bokun-Date': searchDate,
                            'X-Bokun-Signature': searchSignature,
                        },
                    };

                    const apiReq = https.request(options, (apiRes) => {
                        let data = '';
                        apiRes.on('data', (chunk) => { data += chunk; });
                        apiRes.on('end', () => {
                            if (apiRes.statusCode >= 200 && apiRes.statusCode < 300) {
                                resolve(JSON.parse(data));
                            } else {
                                reject(new Error(`Search failed: ${apiRes.statusCode}`));
                            }
                        });
                    });
                    apiReq.on('error', reject);
                    apiReq.write(searchBody);
                    apiReq.end();
                });

                const booking = searchResult.items?.find(b => String(b.id) === String(bookingId));
                if (!booking) throw new Error(`Booking ${bookingId} not found`);
                actualProductBookingId = booking.productBookings?.[0]?.id;
            }

            if (!actualProductBookingId) throw new Error('Could not find productBookingId');

            const editPath = '/booking.json/edit';
            const editDate = new Date().toISOString().replace('T', ' ').substring(0, 19);
            const editMessage = editDate + accessKey + 'POST' + editPath;
            const editSignature = crypto.createHmac('sha1', secretKey).update(editMessage).digest('base64');

            const editActions = [{
                type: 'ActivityPickupAction',
                activityBookingId: parseInt(actualProductBookingId),
                pickup: true,
                pickupPlaceId: parseInt(pickupPlaceId),
                description: pickupPlaceName || '',
            }];

            const editResult = await new Promise((resolve, reject) => {
                const editBody = JSON.stringify(editActions);
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
                        if (apiRes.statusCode >= 200 && apiRes.statusCode < 300) {
                            try { resolve(JSON.parse(data)); } catch (e) { resolve({ success: true }); }
                        } else {
                            reject(new Error(`Edit failed: ${apiRes.statusCode} - ${data}`));
                        }
                    });
                });
                apiReq.on('error', reject);
                apiReq.write(editBody);
                apiReq.end();
            });

            console.log(`✅ Pickup updated successfully`);

            await db.collection('booking_actions').add({
                bookingId,
                action: 'update_pickup',
                pickupPlaceId,
                pickupPlaceName: pickupPlaceName || '',
                performedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            res.json({ success: true, message: `Pickup updated to ${pickupPlaceName || pickupPlaceId}`, result: editResult });

        } catch (error) {
            console.error(`❌ Error updating pickup: ${error.message}`);
            res.status(500).json({ error: error.message });
        }
    }
);

/**
 * Cancel a booking
 */
const cancelBooking = onRequest(
    {
        cors: true,
        invoker: 'public',
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
            const decodedToken = await admin.auth().verifyIdToken(token);
            const uid = decodedToken.uid;

            const requestData = req.body.data || req.body;
            const { bookingId, confirmationCode, reason } = requestData;

            if (!bookingId) {
                res.status(400).json({ error: 'bookingId is required' });
                return;
            }

            if (!reason) {
                res.status(400).json({ error: 'reason is required for cancellation' });
                return;
            }

            if (!confirmationCode) {
                res.status(400).json({ error: 'confirmationCode is required for cancellation' });
                return;
            }

            const accessKey = process.env.BOKUN_ACCESS_KEY;
            const secretKey = process.env.BOKUN_SECRET_KEY;

            if (!accessKey || !secretKey) {
                res.status(500).json({ error: 'Bokun API keys not configured' });
                return;
            }

            // Get current booking for logging
            let currentBooking = null;
            try {
                currentBooking = await makeBokunRequest('GET', `/booking.json/${bookingId}`, null, accessKey, secretKey);
            } catch (e) {
                console.warn('Could not fetch booking details for logging:', e.message);
            }

            const cancelRequest = { note: reason, notify: true };
            const result = await makeBokunRequest('POST', `/booking.json/cancel-booking/${confirmationCode}`, cancelRequest, accessKey, secretKey);

            await db.collection('booking_actions').add({
                bookingId,
                confirmationCode: confirmationCode || '',
                action: 'cancel',
                performedBy: uid,
                performedAt: admin.firestore.FieldValue.serverTimestamp(),
                reason,
                originalData: currentBooking ? { date: currentBooking.startDate, status: currentBooking.status } : null,
                success: true,
                source: 'cloud_function',
            });

            res.status(200).json({ result, success: true });
        } catch (error) {
            console.error('Error in cancelBooking:', error);
            res.status(500).json({ error: error.message });
        }
    }
);

/**
 * Check availability for a booking reschedule
 */
const checkRescheduleAvailability = onDocumentCreated(
    {
        document: 'availability_checks/{checkId}',
        region: 'us-central1',
        secrets: ['BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY', 'BOKUN_OCTO_TOKEN'],
    },
    async (event) => {
        const snapshot = event.data;
        if (!snapshot) return;

        const data = snapshot.data();
        const { bookingId, targetDate } = data;

        console.log(`🔍 Checking availability for booking ${bookingId} on ${targetDate}`);
        await snapshot.ref.update({ status: 'processing' });

        try {
            const accessKey = process.env.BOKUN_ACCESS_KEY;
            const secretKey = process.env.BOKUN_SECRET_KEY;
            const octoToken = process.env.BOKUN_OCTO_TOKEN;

            if (!octoToken) throw new Error('OCTO token not configured');

            const now = new Date();
            const bokunDate = now.toISOString().replace('T', ' ').substring(0, 19);
            const searchPath = '/booking.json/booking-search';
            const message = bokunDate + accessKey + 'POST' + searchPath;
            const signature = crypto.createHmac('sha1', secretKey).update(message).digest('base64');

            const searchResult = await new Promise((resolve, reject) => {
                const postData = JSON.stringify({ id: parseInt(bookingId), limit: 10 });
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
                            resolve(JSON.parse(data));
                        } else {
                            reject(new Error(`Search error: ${apiRes.statusCode}`));
                        }
                    });
                });
                apiReq.on('error', reject);
                apiReq.write(postData);
                apiReq.end();
            });

            const foundBooking = searchResult.items?.find(b => String(b.id) === String(bookingId));
            if (!foundBooking) throw new Error('Booking not found');

            const otaInfo = detectOTABooking(foundBooking);
            const productBooking = foundBooking.productBookings?.[0];
            const productId = productBooking?.product?.id;
            const optionId = productBooking?.activity?.id || productBooking?.rate?.id || productId;

            const availabilityResult = await new Promise((resolve) => {
                const body = JSON.stringify({ productId: String(productId), optionId: String(optionId), localDate: targetDate });
                const options = {
                    hostname: 'api.bokun.io',
                    path: '/octo/v1/availability',
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Content-Length': Buffer.byteLength(body),
                        'Authorization': `Bearer ${octoToken}`,
                    },
                };

                const apiReq = https.request(options, (apiRes) => {
                    let data = '';
                    apiRes.on('data', (chunk) => { data += chunk; });
                    apiRes.on('end', () => {
                        if (apiRes.statusCode >= 200 && apiRes.statusCode < 300) {
                            try { resolve(JSON.parse(data)); } catch (e) { resolve([]); }
                        } else { resolve([]); }
                    });
                });
                apiReq.on('error', () => resolve([]));
                apiReq.write(body);
                apiReq.end();
            });

            const slots = (Array.isArray(availabilityResult) ? availabilityResult : []).map(slot => ({
                id: slot.id,
                localDateTimeStart: slot.localDateTimeStart,
                localDateTimeEnd: slot.localDateTimeEnd,
                available: slot.available,
                status: slot.status,
                vacancies: slot.vacancies,
            }));

            console.log(`📅 Found ${slots.length} availability slots`);

            await snapshot.ref.update({
                status: 'completed',
                productId,
                optionId,
                currentDate: productBooking?.startDate,
                customerName: foundBooking.customer?.firstName
                    ? `${foundBooking.customer.firstName} ${foundBooking.customer.lastName || ''}`.trim()
                    : 'Unknown',
                slots,
                completedAt: admin.firestore.FieldValue.serverTimestamp(),
                isOTABooking: otaInfo.isOTA,
                otaName: otaInfo.otaName,
                otaPortalUrl: otaInfo.otaPortalUrl,
            });

        } catch (error) {
            console.error(`❌ Availability check failed: ${error.message}`);
            await snapshot.ref.update({
                status: 'failed',
                error: error.message,
                failedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
    }
);

/**
 * Firestore Trigger: Process pickup update requests
 * Bypasses Cloud Run IAM issues by using Firestore write-trigger pattern
 */
const onPickupUpdateRequest = onDocumentCreated(
    {
        document: 'pickup_update_requests/{requestId}',
        region: 'us-central1',
        secrets: ['BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY'],
    },
    async (event) => {
        const snapshot = event.data;
        if (!snapshot) {
            console.log('No data in pickup update request');
            return;
        }

        const requestData = snapshot.data();
        const requestId = event.params.requestId;

        if (requestData.status === 'completed' || requestData.status === 'failed') {
            console.log(`Pickup request ${requestId} already processed`);
            return;
        }

        const { bookingId, productBookingId, pickupPlaceId, pickupPlaceName, userId } = requestData;

        console.log(`📍 Processing pickup update request: ${requestId} for booking ${bookingId}`);

        if (!bookingId || !pickupPlaceId) {
            await snapshot.ref.update({
                status: 'failed',
                error: 'bookingId and pickupPlaceId are required',
                failedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            return;
        }

        await snapshot.ref.update({ status: 'processing' });

        try {
            const accessKey = process.env.BOKUN_ACCESS_KEY;
            const secretKey = process.env.BOKUN_SECRET_KEY;

            if (!accessKey || !secretKey) {
                throw new Error('Bokun API keys not configured');
            }

            let actualProductBookingId = productBookingId;

            // If no productBookingId, search for it
            if (!actualProductBookingId) {
                console.log(`🔍 No productBookingId provided, searching for booking ${bookingId}...`);
                const searchPath = '/booking.json/booking-search';
                const searchDate = new Date().toISOString().replace('T', ' ').substring(0, 19);
                const searchMessage = searchDate + accessKey + 'POST' + searchPath;
                const searchSignature = crypto.createHmac('sha1', secretKey).update(searchMessage).digest('base64');

                const searchResult = await new Promise((resolve, reject) => {
                    const searchBody = JSON.stringify({ id: parseInt(bookingId), limit: 10 });
                    const options = {
                        hostname: 'api.bokun.io',
                        path: searchPath,
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json;charset=UTF-8',
                            'Content-Length': Buffer.byteLength(searchBody),
                            'X-Bokun-AccessKey': accessKey,
                            'X-Bokun-Date': searchDate,
                            'X-Bokun-Signature': searchSignature,
                        },
                    };

                    const apiReq = https.request(options, (apiRes) => {
                        let data = '';
                        apiRes.on('data', (chunk) => { data += chunk; });
                        apiRes.on('end', () => {
                            if (apiRes.statusCode >= 200 && apiRes.statusCode < 300) {
                                try { resolve(JSON.parse(data)); } catch (e) { reject(new Error('Failed to parse')); }
                            } else {
                                reject(new Error(`Search failed: ${apiRes.statusCode}`));
                            }
                        });
                    });
                    apiReq.on('error', reject);
                    apiReq.write(searchBody);
                    apiReq.end();
                });

                const booking = searchResult.items?.find(b => String(b.id) === String(bookingId));
                if (!booking) throw new Error(`Booking ${bookingId} not found`);
                actualProductBookingId = booking.productBookings?.[0]?.id;
            }

            if (!actualProductBookingId) throw new Error('Could not find productBookingId');

            console.log(`📍 Using productBookingId: ${actualProductBookingId}`);

            // Execute ActivityPickupAction via Bokun edit API
            const editPath = '/booking.json/edit';
            const editDate = new Date().toISOString().replace('T', ' ').substring(0, 19);
            const editMessage = editDate + accessKey + 'POST' + editPath;
            const editSignature = crypto.createHmac('sha1', secretKey).update(editMessage).digest('base64');

            const editActions = [{
                type: 'ActivityPickupAction',
                activityBookingId: parseInt(actualProductBookingId),
                pickup: true,
                pickupPlaceId: parseInt(pickupPlaceId),
                description: pickupPlaceName || '',
            }];

            await new Promise((resolve, reject) => {
                const editBody = JSON.stringify(editActions);
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
                        if (apiRes.statusCode >= 200 && apiRes.statusCode < 300) {
                            resolve({ success: true });
                        } else {
                            reject(new Error(`Pickup update failed: ${apiRes.statusCode} - ${data}`));
                        }
                    });
                });
                apiReq.on('error', reject);
                apiReq.write(editBody);
                apiReq.end();
            });

            console.log(`✅ Pickup updated successfully`);

            await db.collection('booking_actions').add({
                bookingId,
                action: 'update_pickup',
                pickupPlaceId,
                pickupPlaceName: pickupPlaceName || '',
                performedBy: userId || 'unknown',
                performedAt: admin.firestore.FieldValue.serverTimestamp(),
                success: true,
            });

            await snapshot.ref.update({
                status: 'completed',
                completedAt: admin.firestore.FieldValue.serverTimestamp(),
                message: `Pickup updated to ${pickupPlaceName || pickupPlaceId}`,
            });

            console.log(`✅ Pickup update request completed: ${requestId}`);

        } catch (error) {
            console.error(`❌ Pickup update failed: ${error.message}`);
            await snapshot.ref.update({
                status: 'failed',
                error: error.message,
                failedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
    }
);

/**
 * Firestore Trigger: Process cancel requests
 * Bypasses Cloud Run IAM issues by using Firestore write-trigger pattern
 */
const onCancelRequest = onDocumentCreated(
    {
        document: 'cancel_requests/{requestId}',
        region: 'us-central1',
        secrets: ['BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY'],
    },
    async (event) => {
        const snapshot = event.data;
        if (!snapshot) {
            console.log('No data in cancel request');
            return;
        }

        const requestData = snapshot.data();
        const requestId = event.params.requestId;

        if (requestData.status === 'completed' || requestData.status === 'failed') {
            console.log(`Cancel request ${requestId} already processed`);
            return;
        }

        const { bookingId, confirmationCode, reason, userId } = requestData;

        console.log(`🗑️ Processing cancel request: ${requestId} for booking ${bookingId}`);

        if (!bookingId || !confirmationCode || !reason) {
            await snapshot.ref.update({
                status: 'failed',
                error: 'bookingId, confirmationCode, and reason are required',
                failedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            return;
        }

        await snapshot.ref.update({ status: 'processing' });

        try {
            const accessKey = process.env.BOKUN_ACCESS_KEY;
            const secretKey = process.env.BOKUN_SECRET_KEY;

            if (!accessKey || !secretKey) {
                throw new Error('Bokun API keys not configured');
            }

            // Get current booking for logging
            let currentBooking = null;
            try {
                currentBooking = await makeBokunRequest('GET', `/booking.json/${bookingId}`, null, accessKey, secretKey);
            } catch (e) {
                console.warn('Could not fetch booking details for logging:', e.message);
            }

            // Cancel the booking
            const cancelRequest = { note: reason, notify: true };
            await makeBokunRequest('POST', `/booking.json/cancel-booking/${confirmationCode}`, cancelRequest, accessKey, secretKey);

            console.log(`✅ Booking cancelled successfully`);

            await db.collection('booking_actions').add({
                bookingId,
                confirmationCode,
                action: 'cancel',
                performedBy: userId || 'unknown',
                performedAt: admin.firestore.FieldValue.serverTimestamp(),
                reason,
                originalData: currentBooking ? { date: currentBooking.startDate, status: currentBooking.status } : null,
                success: true,
                source: 'firestore_trigger',
            });

            await snapshot.ref.update({
                status: 'completed',
                completedAt: admin.firestore.FieldValue.serverTimestamp(),
                message: `Booking ${confirmationCode} cancelled successfully`,
            });

            console.log(`✅ Cancel request completed: ${requestId}`);

        } catch (error) {
            console.error(`❌ Cancel failed: ${error.message}`);
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
    checkRescheduleAvailability,
    getPickupPlaces,
    updatePickupLocation,
    cancelBooking,
    onPickupUpdateRequest,
    onCancelRequest,
    detectOTABooking,
};
