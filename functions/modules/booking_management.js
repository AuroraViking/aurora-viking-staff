/**
 * Booking Management Module
 * Handles reschedule, cancel, and pickup location changes
 */
const { onRequest } = require('firebase-functions/v2/https');
const { onCall } = require('firebase-functions/v2/https');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const crypto = require('crypto');
const https = require('https');
const { admin, db } = require('../utils/firebase');
const { makeBokunRequest } = require('../utils/bokun_client');

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
        today.setHours(0, 0, 0, 0); // Start of today
        const requestedDate = new Date(newDate + 'T00:00:00');

        if (requestedDate < today) {
            console.error(`❌ Requested date ${newDate} is in the past (today is ${today.toISOString().split('T')[0]})`);
            await snapshot.ref.update({
                status: 'failed',
                error: `Cannot reschedule to a past date (${newDate}). Today is ${today.toISOString().split('T')[0]}.`,
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
            const signature = crypto
                .createHmac('sha1', secretKey)
                .update(message)
                .digest('base64');

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
                            try {
                                resolve(JSON.parse(data));
                            } catch (e) {
                                reject(new Error('Failed to parse search response'));
                            }
                        } else {
                            reject(new Error(`Bokun search error: ${apiRes.statusCode}`));
                        }
                    });
                });

                apiReq.on('error', (error) => reject(error));
                apiReq.write(postData);
                apiReq.end();
            });

            const foundBooking = searchResult.items?.find(b => String(b.id) === String(bookingId));
            if (!foundBooking) {
                throw new Error(`Booking ${bookingId} not found`);
            }

            console.log(`✅ Found booking ${bookingId} (${foundBooking.confirmationCode})`);

            // Log if this is a reseller booking (for debugging, but we'll still try to reschedule)
            const externalRef = foundBooking.externalBookingReference || '';
            const confirmCode = foundBooking.confirmationCode || '';
            const isResellerBooking =
                externalRef.toLowerCase().includes('viator') ||
                externalRef.toLowerCase().includes('gyg') ||
                confirmCode.toUpperCase().startsWith('VIA-') ||
                confirmCode.toUpperCase().startsWith('GYG-') ||
                confirmCode.toUpperCase().startsWith('TDI-');

            if (isResellerBooking) {
                console.log(`📌 Note: This is a reseller booking (${confirmCode}), attempting reschedule anyway...`);
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

            console.log(`📦 Product ID: ${productId}, Option ID: ${optionId}, Current date: ${currentDate}, New date: ${newDate}`);

            // Helper function for OCTO API calls
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

                    if (postData) {
                        options.headers['Content-Length'] = Buffer.byteLength(postData);
                    }

                    console.log(`📡 OCTO ${method} ${options.path}`);

                    const apiReq = https.request(options, (apiRes) => {
                        let data = '';
                        apiRes.on('data', (chunk) => { data += chunk; });
                        apiRes.on('end', () => {
                            console.log(`📡 OCTO Response: ${apiRes.statusCode}`);

                            if (apiRes.statusCode >= 200 && apiRes.statusCode < 300) {
                                try {
                                    resolve(data ? JSON.parse(data) : {});
                                } catch (e) {
                                    resolve(data);
                                }
                            } else {
                                reject(new Error(`OCTO API error: ${apiRes.statusCode} - ${data}`));
                            }
                        });
                    });

                    apiReq.on('error', (error) => reject(error));
                    if (postData) {
                        apiReq.write(postData);
                    }
                    apiReq.end();
                });
            };

            // Get OCTO products to find correct IDs
            console.log(`🔍 Fetching OCTO products...`);
            let octoProductId = String(productId);
            let octoOptionId = String(optionId);
            let defaultUnitId = null;

            try {
                const octoProducts = await octoRequest('GET', '/products');
                console.log(`📦 OCTO returned ${Array.isArray(octoProducts) ? octoProducts.length : 0} products`);

                if (Array.isArray(octoProducts) && octoProducts.length > 0) {
                    const matchingProduct = octoProducts.find(p =>
                        String(p.id) === String(productId) ||
                        p.internalName?.includes(String(productId))
                    );

                    let optionToUse = null;
                    if (matchingProduct) {
                        octoProductId = String(matchingProduct.id);
                        if (matchingProduct.options && matchingProduct.options.length > 0) {
                            optionToUse = matchingProduct.options[0];
                            octoOptionId = String(optionToUse.id);
                        }
                    } else {
                        const firstProduct = octoProducts[0];
                        octoProductId = String(firstProduct.id);
                        if (firstProduct.options && firstProduct.options.length > 0) {
                            optionToUse = firstProduct.options[0];
                            octoOptionId = String(optionToUse.id);
                        }
                    }

                    if (optionToUse && optionToUse.units && optionToUse.units.length > 0) {
                        defaultUnitId = String(optionToUse.units[0].id);
                    }
                }
            } catch (e) {
                console.log(`⚠️ Could not fetch OCTO products: ${e.message}`);
            }

            // Check availability for the new date
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

            // Try to find OCTO booking (try multiple reference formats)
            let octoBookingUuid = null;
            try {
                // Try searching by supplier reference (booking ID)
                let octoBookings = await octoRequest('GET', `/bookings?supplierReference=${bookingId}`);
                if (Array.isArray(octoBookings) && octoBookings.length > 0) {
                    octoBookingUuid = octoBookings[0].uuid;
                    console.log(`✅ Found OCTO booking UUID by bookingId: ${octoBookingUuid}`);
                }

                // If not found, try by confirmation code
                if (!octoBookingUuid) {
                    const confirmCodeForSearch = confirmationCode || foundBooking.confirmationCode;
                    octoBookings = await octoRequest('GET', `/bookings?resellerReference=${confirmCodeForSearch}`);
                    if (Array.isArray(octoBookings) && octoBookings.length > 0) {
                        octoBookingUuid = octoBookings[0].uuid;
                        console.log(`✅ Found OCTO booking UUID by confirmationCode: ${octoBookingUuid}`);
                    }
                }
            } catch (e) {
                console.log(`⚠️ Could not find OCTO booking: ${e.message}`);
            }

            if (!octoBookingUuid) {
                // OCTO booking not found - use cancel + rebook strategy
                console.log(`⚠️ OCTO booking not found - using cancel + rebook strategy`);

                // Extract customer and booking info for rebooking
                const customer = foundBooking.customer || {};
                const customerContact = {
                    fullName: `${customer.firstName || ''} ${customer.lastName || ''}`.trim(),
                    firstName: customer.firstName || '',
                    lastName: customer.lastName || '',
                    emailAddress: customer.email || customer.emailAddress || '',
                    phoneNumber: customer.phoneNumber || customer.phone || '',
                };

                // Count participants
                let totalParticipants = 0;
                for (const pcb of (productBooking.priceCategoryBookings || [])) {
                    totalParticipants += pcb.persons || pcb.qty || 1;
                }
                if (totalParticipants === 0) {
                    totalParticipants = productBooking.totalParticipants || foundBooking.totalParticipants || 1;
                }

                // Extract pickup info
                const fields = productBooking.fields || {};
                let pickupLocation = null;
                let pickupLocationId = null;

                if (fields.pickupPlace) {
                    pickupLocation = fields.pickupPlace.title || fields.pickupPlace.name || null;
                    pickupLocationId = fields.pickupPlace.id ? String(fields.pickupPlace.id) : null;
                }
                if (!pickupLocation && fields.pickupPlaceDescription) {
                    pickupLocation = fields.pickupPlaceDescription;
                }
                if (!pickupLocation && productBooking.pickupPlace) {
                    pickupLocation = productBooking.pickupPlace.title || productBooking.pickupPlace.name || null;
                    pickupLocationId = productBooking.pickupPlace.id ? String(productBooking.pickupPlace.id) : null;
                }

                console.log(`📋 Customer: ${customerContact.fullName}, Participants: ${totalParticipants}`);
                console.log(`📋 Pickup: ${pickupLocation || 'None'}`);

                // Cancel the existing booking - try OCTO API first, then fall back to Bokun REST
                const bookingConfirmCode = confirmationCode || foundBooking.confirmationCode;
                console.log(`🚫 Cancelling existing booking ${bookingConfirmCode}...`);

                let cancelSuccess = false;

                // Try OCTO API cancellation first (might work for reseller bookings)
                if (octoBookingUuid) {
                    try {
                        console.log(`🚫 Trying OCTO API cancel for ${octoBookingUuid}...`);
                        await octoRequest('DELETE', `/bookings/${octoBookingUuid}`);
                        cancelSuccess = true;
                        console.log(`✅ OCTO cancellation successful`);
                    } catch (octoError) {
                        console.log(`⚠️ OCTO cancel failed: ${octoError.message}, trying Bokun REST...`);
                    }
                }

                // Fall back to Bokun REST API if OCTO didn't work
                if (!cancelSuccess) {
                    const cancelPath = `/booking.json/cancel-booking/${bookingConfirmCode}`;
                    const cancelDate = new Date().toISOString().replace('T', ' ').substring(0, 19);
                    const cancelMessage = cancelDate + accessKey + 'POST' + cancelPath;
                    const cancelSignature = crypto
                        .createHmac('sha1', secretKey)
                        .update(cancelMessage)
                        .digest('base64');

                    await new Promise((resolve, reject) => {
                        const cancelBody = JSON.stringify({
                            reason: `Rescheduled to ${newDate}. ${reason || 'Rescheduled via admin app'}`,
                        });

                        const options = {
                            hostname: 'api.bokun.io',
                            path: cancelPath,
                            method: 'POST',
                            headers: {
                                'Content-Type': 'application/json;charset=UTF-8',
                                'Content-Length': Buffer.byteLength(cancelBody),
                                'X-Bokun-AccessKey': accessKey,
                                'X-Bokun-Date': cancelDate,
                                'X-Bokun-Signature': cancelSignature,
                            },
                        };

                        const apiReq = https.request(options, (apiRes) => {
                            let data = '';
                            apiRes.on('data', (chunk) => { data += chunk; });
                            apiRes.on('end', () => {
                                console.log(`🚫 Bokun cancel response: ${apiRes.statusCode}`);
                                if (apiRes.statusCode >= 200 && apiRes.statusCode < 400) {
                                    resolve({ success: true });
                                } else {
                                    reject(new Error(`Cancel failed: ${apiRes.statusCode} - ${data}`));
                                }
                            });
                        });

                        apiReq.on('error', (error) => reject(error));
                        apiReq.write(cancelBody);
                        apiReq.end();
                    });
                }

                console.log(`✅ Booking cancelled successfully`);

                // Create new booking via OCTO
                console.log(`📝 Creating new booking for ${newDate}...`);

                const unitItems = [];
                const unitIdToUse = defaultUnitId || octoOptionId;
                for (let i = 0; i < totalParticipants; i++) {
                    unitItems.push({ unitId: unitIdToUse });
                }

                const newBookingRequest = {
                    productId: octoProductId,
                    optionId: octoOptionId,
                    availabilityId: availabilityId,
                    unitItems: unitItems.length > 0 ? unitItems : [{ unitId: unitIdToUse }],
                    notes: `Rebook from ${confirmationCode || bookingId}. Original date: ${currentDate}. ${pickupLocation ? 'Pickup: ' + pickupLocation + '. ' : ''}Reason: ${reason || 'Customer request'}`,
                };

                const newBooking = await octoRequest('POST', '/bookings', newBookingRequest);
                console.log(`✅ New booking created: ${newBooking.uuid || newBooking.id || 'unknown'}`);

                // Confirm the booking
                if (newBooking.uuid) {
                    console.log(`✔️ Confirming new booking...`);
                    const confirmRequest = {
                        contact: {
                            firstName: customerContact.firstName || 'Guest',
                            lastName: customerContact.lastName || 'Customer',
                            emailAddress: customerContact.emailAddress || 'no-email@placeholder.com',
                            phoneNumber: customerContact.phoneNumber || '',
                        },
                    };

                    await octoRequest('POST', `/bookings/${newBooking.uuid}/confirm`, confirmRequest);
                    console.log(`✅ Booking confirmed!`);

                    // Try to set pickup location via REST API
                    if (pickupLocation && pickupLocationId) {
                        console.log(`📍 Setting pickup location...`);
                        await new Promise(resolve => setTimeout(resolve, 2000));

                        // Search for the new booking to get productBookingId
                        const newConfirmationCode = newBooking.supplierReference;
                        const newBookingId = newConfirmationCode.replace(/[^0-9]/g, '');

                        const searchPath2 = '/booking.json/booking-search';
                        const searchDate2 = new Date().toISOString().replace('T', ' ').substring(0, 19);
                        const searchMessage2 = searchDate2 + accessKey + 'POST' + searchPath2;
                        const searchSignature2 = crypto
                            .createHmac('sha1', secretKey)
                            .update(searchMessage2)
                            .digest('base64');

                        try {
                            const searchResult2 = await new Promise((resolve, reject) => {
                                const searchBody = JSON.stringify({ bookingId: parseInt(newBookingId) });
                                const options = {
                                    hostname: 'api.bokun.io',
                                    path: searchPath2,
                                    method: 'POST',
                                    headers: {
                                        'Content-Type': 'application/json;charset=UTF-8',
                                        'Content-Length': Buffer.byteLength(searchBody),
                                        'X-Bokun-AccessKey': accessKey,
                                        'X-Bokun-Date': searchDate2,
                                        'X-Bokun-Signature': searchSignature2,
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

                            const actualProductBookingId = searchResult2.items?.[0]?.productBookings?.[0]?.id;
                            if (actualProductBookingId) {
                                // Apply pickup using ActivityPickupAction
                                const editPath = '/booking.json/edit';
                                const editDate = new Date().toISOString().replace('T', ' ').substring(0, 19);
                                const editMessage = editDate + accessKey + 'POST' + editPath;
                                const editSignature = crypto
                                    .createHmac('sha1', secretKey)
                                    .update(editMessage)
                                    .digest('base64');

                                const editActions = [{
                                    type: 'ActivityPickupAction',
                                    activityBookingId: parseInt(actualProductBookingId),
                                    pickup: true,
                                    pickupPlaceId: parseInt(pickupLocationId),
                                    description: pickupLocation,
                                }];

                                await new Promise((resolve) => {
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
                                            console.log(`📍 Edit pickup response: ${apiRes.statusCode}`);
                                            resolve({ success: apiRes.statusCode >= 200 && apiRes.statusCode < 400 });
                                        });
                                    });

                                    apiReq.on('error', () => resolve({ success: false }));
                                    apiReq.write(editBody);
                                    apiReq.end();
                                });
                            }
                        } catch (e) {
                            console.log(`⚠️ Could not set pickup: ${e.message}`);
                        }
                    }
                }

                // Log success
                await db.collection('booking_actions').add({
                    bookingId,
                    confirmationCode: confirmationCode || foundBooking.confirmationCode,
                    customerName,
                    action: 'reschedule',
                    performedBy: userId || 'unknown',
                    performedAt: admin.firestore.FieldValue.serverTimestamp(),
                    reason: reason || 'Rescheduled via admin app',
                    originalData: { date: currentDate },
                    newData: {
                        date: newDate,
                        availabilityId,
                        newBookingUuid: newBooking.uuid,
                        newBookingId: newBooking.id,
                    },
                    success: true,
                    method: 'cancel_and_rebook',
                    source: 'octo_api',
                });

                await snapshot.ref.update({
                    status: 'completed',
                    method: 'cancel_and_rebook',
                    availabilityId,
                    newBookingUuid: newBooking.uuid || null,
                    newBookingId: newBooking.id || null,
                    customerName,
                    originalDate: currentDate,
                    completedAt: admin.firestore.FieldValue.serverTimestamp(),
                    message: `Booking rescheduled to ${newDate} via cancel + rebook`,
                });

                console.log(`✅ Reschedule completed via cancel + rebook: ${requestId}`);
                return;
            }

            // If we have OCTO booking UUID, PATCH it directly
            console.log(`📝 Updating booking ${octoBookingUuid} to new date...`);

            await octoRequest('PATCH', `/bookings/${octoBookingUuid}`, {
                availabilityId: availabilityId,
                unitItems: productBooking.priceCategoryBookings?.map(pcb => ({
                    unitId: pcb.priceCategoryBooking?.priceCategory?.id || pcb.id,
                })) || [],
            });

            console.log(`✅ Booking updated successfully via OCTO API!`);

            // Log success
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

            await db.collection('booking_actions').add({
                bookingId,
                confirmationCode: confirmationCode || '',
                action: 'reschedule',
                performedBy: userId || 'unknown',
                performedAt: admin.firestore.FieldValue.serverTimestamp(),
                reason: reason || 'Attempted reschedule',
                newData: { date: newDate },
                success: false,
                errorMessage: error.message,
                source: 'firestore_trigger',
            });

            await snapshot.ref.update({
                status: 'failed',
                error: error.message,
                failedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
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

            if (!octoToken) {
                throw new Error('OCTO token not configured');
            }

            // Search for the booking
            const now = new Date();
            const bokunDate = now.toISOString().replace('T', ' ').substring(0, 19);
            const searchPath = '/booking.json/booking-search';
            const message = bokunDate + accessKey + 'POST' + searchPath;
            const signature = crypto
                .createHmac('sha1', secretKey)
                .update(message)
                .digest('base64');

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
            if (!foundBooking) {
                throw new Error('Booking not found');
            }

            const productBooking = foundBooking.productBookings?.[0];
            const productId = productBooking?.product?.id;
            const optionId = productBooking?.activity?.id || productBooking?.rate?.id || productId;

            // Query OCTO API for availability
            const availabilityResult = await new Promise((resolve) => {
                const body = JSON.stringify({
                    productId: String(productId),
                    optionId: String(optionId),
                    localDate: targetDate,
                });

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
                            try {
                                resolve(JSON.parse(data));
                            } catch (e) {
                                resolve([]);
                            }
                        } else {
                            resolve([]);
                        }
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
 * Get pickup places for an activity/product
 */
const getPickupPlaces = onRequest(
    {
        cors: true,
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
            const pickupSignature = crypto
                .createHmac('sha1', secretKey)
                .update(pickupMessage)
                .digest('base64');

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
                                if (parsed.pickupPlaces) {
                                    resolve(parsed.pickupPlaces);
                                } else if (parsed.pickupDropoffPlaces) {
                                    resolve(parsed.pickupDropoffPlaces);
                                } else if (parsed.items) {
                                    resolve(parsed.items);
                                } else {
                                    resolve(parsed);
                                }
                            } catch (e) {
                                resolve([]);
                            }
                        } else {
                            resolve([]);
                        }
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
                // Search for the booking to get productBookingId
                const searchPath = '/booking.json/booking-search';
                const searchDate = new Date().toISOString().replace('T', ' ').substring(0, 19);
                const searchMessage = searchDate + accessKey + 'POST' + searchPath;
                const searchSignature = crypto
                    .createHmac('sha1', secretKey)
                    .update(searchMessage)
                    .digest('base64');

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
                if (!booking) {
                    throw new Error(`Booking ${bookingId} not found`);
                }
                actualProductBookingId = booking.productBookings?.[0]?.id;
            }

            if (!actualProductBookingId) {
                throw new Error('Could not find productBookingId');
            }

            // Use REST API with ActivityPickupAction
            const editPath = '/booking.json/edit';
            const editDate = new Date().toISOString().replace('T', ' ').substring(0, 19);
            const editMessage = editDate + accessKey + 'POST' + editPath;
            const editSignature = crypto
                .createHmac('sha1', secretKey)
                .update(editMessage)
                .digest('base64');

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
                            try {
                                resolve(JSON.parse(data));
                            } catch (e) {
                                resolve({ success: true, raw: data });
                            }
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

            res.json({
                success: true,
                message: `Pickup updated to ${pickupPlaceName || pickupPlaceId}`,
                result: editResult,
            });

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

            const accessKey = process.env.BOKUN_ACCESS_KEY;
            const secretKey = process.env.BOKUN_SECRET_KEY;

            if (!accessKey || !secretKey) {
                res.status(500).json({ error: 'Bokun API keys not configured' });
                return;
            }

            // Get current booking for logging
            let currentBooking = null;
            try {
                currentBooking = await makeBokunRequest(
                    'GET',
                    `/booking.json/${bookingId}`,
                    null,
                    accessKey,
                    secretKey
                );
            } catch (e) {
                console.warn('Could not fetch booking details for logging:', e.message);
            }

            if (!confirmationCode) {
                res.status(400).json({ error: 'confirmationCode is required for cancellation' });
                return;
            }

            const cancelRequest = {
                note: reason,
                notify: true,
            };

            const result = await makeBokunRequest(
                'POST',
                `/booking.json/cancel-booking/${confirmationCode}`,
                cancelRequest,
                accessKey,
                secretKey
            );

            await db.collection('booking_actions').add({
                bookingId,
                confirmationCode: confirmationCode || '',
                action: 'cancel',
                performedBy: uid,
                performedAt: admin.firestore.FieldValue.serverTimestamp(),
                reason,
                originalData: currentBooking ? {
                    date: currentBooking.startDate,
                    status: currentBooking.status,
                    totalParticipants: currentBooking.totalParticipants,
                } : null,
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

module.exports = {
    getBookingDetails,
    rescheduleBooking,
    onRescheduleRequest,
    checkRescheduleAvailability,
    getPickupPlaces,
    updatePickupLocation,
    cancelBooking,
};
