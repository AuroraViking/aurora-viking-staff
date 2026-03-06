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
function buildCancellationSms(firstName, confirmationCode) {
    let portalUrl = 'https://www.auroraviking.com/bookings';
    if (confirmationCode) {
        portalUrl += `?code=${encodeURIComponent(confirmationCode)}`;
    }

    return `Hi ${firstName || 'there'}, unfortunately tonight's Northern Lights tour has been cancelled due to unfavorable weather conditions for aurora sightings.\n\nReschedule or cancel instantly using our Booking Portal: ${portalUrl}\n\nYour confirmation code: ${confirmationCode || 'N/A'}\nEnter it on the portal to manage your booking.\n\n— Aurora Viking`;
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
        });
    }

    return customers;
}

/**
 * Internal function to send cancellation SMS to all customers for a date
 */
async function sendCancellationSmsInternal(dateString) {
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
            const messageBody = buildCancellationSms(customer.firstName, customer.confirmationCode);

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
    sendTestSms,
};
