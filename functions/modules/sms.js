/**
 * SMS Module
 * Handles sending SMS notifications via Twilio
 */
const { onCall } = require('firebase-functions/v2/https');
const { admin, db } = require('../utils/firebase');

// Twilio client setup (lazy-initialized)
let twilioClient = null;

function getTwilioClient() {
    if (!twilioClient) {
        const accountSid = process.env.TWILIO_ACCOUNT_SID;
        const authToken = process.env.TWILIO_AUTH_TOKEN;

        if (!accountSid || !authToken) {
            throw new Error('Twilio credentials not configured');
        }

        const twilio = require('twilio');
        twilioClient = twilio(accountSid, authToken);
    }
    return twilioClient;
}

/**
 * Build the cancellation SMS message
 */
// Default cancellation SMS body
const DEFAULT_CANCEL_SMS_BODY = "unfortunately tonight's Northern Lights tour has been cancelled due to unfavorable weather conditions for aurora sightings.";

function buildCancellationSms(firstName, confirmationCode, customBody) {
    let portalUrl = 'https://www.auroraviking.com/bookings';
    if (confirmationCode) {
        portalUrl += `?code=${encodeURIComponent(confirmationCode)}`;
    }

    const body = customBody || DEFAULT_CANCEL_SMS_BODY;
    return `Hi ${firstName || 'there'}, ${body}\n\nReschedule or cancel instantly using our Booking Portal: ${portalUrl}\n\nYour confirmation code: ${confirmationCode || 'N/A'}\nEnter it on the portal to manage your booking.\n\n— Aurora Viking`;
}

/**
 * Extract phone numbers from cached bookings
 */
function extractPhoneData(bookings) {
    const seen = new Set();
    const customers = [];

    for (const booking of bookings) {
        const phone = booking.customerPhone || booking.phoneNumber ||
            booking.phone || booking.customer?.phoneNumber ||
            booking.customer?.phone || '';

        if (!phone || seen.has(phone)) continue;
        seen.add(phone);

        // Normalize phone number - ensure it starts with +
        let normalizedPhone = phone.replace(/\s+/g, '').replace(/[()-]/g, '');
        if (!normalizedPhone.startsWith('+')) {
            // If no country code, skip - we can't guess
            console.log(`⚠️ Skipping phone without country code: ${phone}`);
            continue;
        }

        const fullName = booking.customerFullName ||
            ((booking.customer?.firstName || '') + ' ' + (booking.customer?.lastName || '')).trim() ||
            'Valued Customer';
        const firstName = fullName.split(' ')[0] || 'there';
        const confirmationCode = booking.confirmationCode || '';

        customers.push({
            phone: normalizedPhone,
            firstName,
            fullName,
            confirmationCode,
            pickupLocation: booking.pickupPlaceName || booking.pickupLocation || '',
            departureTime: booking.departureTime || '',
        });
    }

    return customers;
}

/**
 * Internal function to send cancellation SMS to all customers for a date
 */
async function sendCancellationSmsInternal(dateString, customSmsBody) {
    console.log(`📱 [Internal] Sending cancellation SMS for ${dateString}...`);

    try {
        const client = getTwilioClient();
        const messagingServiceSid = process.env.TWILIO_MESSAGING_SERVICE_SID;
        const fromNumber = process.env.TWILIO_PHONE_NUMBER;

        if (!messagingServiceSid && !fromNumber) {
            console.log('⚠️ No Twilio phone number or messaging service configured');
            return { success: false, smsSent: 0, error: 'Twilio sender not configured' };
        }

        // Fetch bookings from cached_bookings
        let bookings = [];
        const cachedDoc = await db.collection('cached_bookings').doc(dateString).get();
        if (cachedDoc.exists) {
            const data = cachedDoc.data();
            bookings = data.bookings || [];
        }

        // Also merge manual bookings
        const manualSnap = await db.collection('manual_bookings')
            .where('date', '==', dateString)
            .get();
        manualSnap.docs.forEach(doc => {
            const manual = doc.data().booking;
            if (manual) bookings.push(manual);
        });

        console.log(`📋 Found ${bookings.length} bookings`);

        if (bookings.length === 0) {
            return { success: true, smsSent: 0, message: 'No bookings found' };
        }

        // Extract phone data
        const customers = extractPhoneData(bookings);
        console.log(`📱 Found ${customers.length} unique customers with phone numbers`);

        if (customers.length === 0) {
            return { success: true, smsSent: 0, message: 'No customer phone numbers found' };
        }

        // Send SMS to each customer
        let smsSent = 0;
        const failedSms = [];

        for (const customer of customers) {
            const messageBody = buildCancellationSms(customer.firstName, customer.confirmationCode, customSmsBody);

            try {
                const messageOptions = {
                    body: messageBody,
                    to: customer.phone,
                };

                // Prefer MessagingServiceSid, fall back to From number
                if (messagingServiceSid) {
                    messageOptions.messagingServiceSid = messagingServiceSid;
                } else {
                    messageOptions.from = fromNumber;
                }

                await client.messages.create(messageOptions);
                smsSent++;
                console.log(`✅ SMS sent to ${customer.firstName} (${customer.phone})`);
            } catch (sendError) {
                console.error(`❌ Failed to send SMS to ${customer.phone}: ${sendError.message}`);
                failedSms.push({ phone: customer.phone, error: sendError.message });
            }

            // Small delay to avoid rate limits
            if (customers.length > 5) {
                await new Promise(resolve => setTimeout(resolve, 200));
            }
        }

        // Log the SMS send action
        await db.collection('tour_status_sms').add({
            date: dateString,
            totalBookings: bookings.length,
            uniqueCustomers: customers.length,
            smsSent,
            failedSms,
            sentAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`✅ Cancellation SMS complete: ${smsSent}/${customers.length} sent`);

        return {
            success: true,
            smsSent,
            customersWithPhones: customers.length,
            failedCount: failedSms.length,
        };

    } catch (error) {
        console.error('❌ Error in sendCancellationSmsInternal:', error);
        return { success: false, smsSent: 0, error: error.message };
    }
}

/**
 * Build Google Maps search URL for a pickup location
 */
function buildMapsUrl(pickupLocation) {
    if (!pickupLocation) return '';
    const query = encodeURIComponent(`${pickupLocation} Reykjavik Iceland`);
    return `https://www.google.com/maps/search/?api=1&query=${query}`;
}

/**
 * Build the ON (tour is running) SMS message
 */
function buildOnSms(firstName, pickupLocation, departureTime) {
    let msg = `Hi ${firstName || 'there'}, the Northern Lights tour is ON tonight! 🌌`;

    if (pickupLocation) {
        msg += `\n\n📍 Your pickup: ${pickupLocation}`;
    }
    if (departureTime) {
        msg += `\n🕐 Pickups start at ${departureTime} — it may take up to 30 min to reach all stops, so please be patient if the bus isn't there right away.`;
    }
    if (pickupLocation) {
        msg += `\n\n📍 Find it on Maps: ${buildMapsUrl(pickupLocation)}`;
    }

    msg += `\n\nDress warm! — Aurora Viking`;
    return msg;
}

/**
 * Internal function to send ON SMS to all customers for a date
 */
async function sendOnSmsInternal(dateString) {
    console.log(`📱 [Internal] Sending ON SMS for ${dateString}...`);

    try {
        const client = getTwilioClient();
        const messagingServiceSid = process.env.TWILIO_MESSAGING_SERVICE_SID;
        const fromNumber = process.env.TWILIO_PHONE_NUMBER;

        if (!messagingServiceSid && !fromNumber) {
            console.log('⚠️ No Twilio phone number or messaging service configured');
            return { success: false, smsSent: 0, error: 'Twilio sender not configured' };
        }

        // Fetch bookings from cached_bookings
        let bookings = [];
        const cachedDoc = await db.collection('cached_bookings').doc(dateString).get();
        if (cachedDoc.exists) {
            const data = cachedDoc.data();
            bookings = data.bookings || [];
        }

        // Also merge manual bookings
        const manualSnap = await db.collection('manual_bookings')
            .where('date', '==', dateString)
            .get();
        manualSnap.docs.forEach(doc => {
            const manual = doc.data().booking;
            if (manual) bookings.push(manual);
        });

        console.log(`📋 Found ${bookings.length} bookings`);

        if (bookings.length === 0) {
            return { success: true, smsSent: 0, message: 'No bookings found' };
        }

        // Extract phone data (now includes pickup info)
        const customers = extractPhoneData(bookings);
        console.log(`📱 Found ${customers.length} unique customers with phone numbers`);

        if (customers.length === 0) {
            return { success: true, smsSent: 0, message: 'No customer phone numbers found' };
        }

        // Send SMS to each customer
        let smsSent = 0;
        const failedSms = [];

        for (const customer of customers) {
            const messageBody = buildOnSms(customer.firstName, customer.pickupLocation, customer.departureTime);

            try {
                const messageOptions = {
                    body: messageBody,
                    to: customer.phone,
                };

                if (messagingServiceSid) {
                    messageOptions.messagingServiceSid = messagingServiceSid;
                } else {
                    messageOptions.from = fromNumber;
                }

                await client.messages.create(messageOptions);
                smsSent++;
                console.log(`✅ ON SMS sent to ${customer.firstName} (${customer.phone})`);
            } catch (sendError) {
                console.error(`❌ Failed to send ON SMS to ${customer.phone}: ${sendError.message}`);
                failedSms.push({ phone: customer.phone, error: sendError.message });
            }

            // Small delay to avoid rate limits
            if (customers.length > 5) {
                await new Promise(resolve => setTimeout(resolve, 200));
            }
        }

        // Log the SMS send action
        await db.collection('tour_status_sms').add({
            date: dateString,
            type: 'ON',
            totalBookings: bookings.length,
            uniqueCustomers: customers.length,
            smsSent,
            failedSms,
            sentAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`✅ ON SMS complete: ${smsSent}/${customers.length} sent`);

        return {
            success: true,
            smsSent,
            customersWithPhones: customers.length,
            failedCount: failedSms.length,
        };

    } catch (error) {
        console.error('❌ Error in sendOnSmsInternal:', error);
        return { success: false, smsSent: 0, error: error.message };
    }
}

/**
 * Send a test SMS to verify Twilio is working (admin only)
 */
const sendTestSms = onCall(
    {
        region: 'us-central1',
        secrets: ['TWILIO_ACCOUNT_SID', 'TWILIO_AUTH_TOKEN', 'TWILIO_MESSAGING_SERVICE_SID'],
    },
    async (request) => {
        if (!request.auth) {
            throw new Error('You must be logged in to send test SMS');
        }

        const { phoneNumber } = request.data;

        if (!phoneNumber) {
            throw new Error('phoneNumber is required');
        }

        console.log(`🧪 Sending test SMS to ${phoneNumber}...`);

        try {
            const client = getTwilioClient();
            const messagingServiceSid = process.env.TWILIO_MESSAGING_SERVICE_SID;
            const fromNumber = process.env.TWILIO_PHONE_NUMBER;

            const messageOptions = {
                body: '🧪 Aurora Viking test SMS — If you received this, SMS notifications are working! 🎉',
                to: phoneNumber,
            };

            if (messagingServiceSid) {
                messageOptions.messagingServiceSid = messagingServiceSid;
            } else if (fromNumber) {
                messageOptions.from = fromNumber;
            } else {
                throw new Error('No Twilio sender configured');
            }

            const message = await client.messages.create(messageOptions);

            console.log(`✅ Test SMS sent: ${message.sid}`);

            return {
                success: true,
                messageSid: message.sid,
                to: phoneNumber,
            };
        } catch (error) {
            console.error(`❌ Test SMS failed: ${error.message}`);
            throw new Error(`SMS failed: ${error.message}`);
        }
    }
);

module.exports = {
    sendCancellationSmsInternal,
    sendOnSmsInternal,
    sendTestSms,
};
