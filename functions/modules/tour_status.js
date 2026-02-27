/**
 * Tour Status Module
 * Handles tour ON/OFF status for daily operations
 */
const { onRequest, onCall } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { google } = require('googleapis');
const https = require('https');
const crypto = require('crypto');
const { admin, db } = require('../utils/firebase');
const { sendNotificationToAdminsOnly } = require('../utils/notifications');

// Gmail OAuth2 client setup
function getGmailOAuth2Client(clientId, clientSecret) {
    return new google.auth.OAuth2(
        clientId,
        clientSecret,
        'https://us-central1-aurora-viking-staff.cloudfunctions.net/gmailOAuthCallback'
    );
}

// Get Gmail tokens for a specific email
async function getGmailTokens(email) {
    const emailId = email.replace(/[.@]/g, '_');
    const doc = await db.collection('system').doc('gmail_accounts').collection('accounts').doc(emailId).get();
    if (doc.exists) {
        return doc.data();
    }
    // Fallback to old location
    const oldDoc = await db.collection('system').doc('gmail_tokens').get();
    if (oldDoc.exists) {
        return oldDoc.data();
    }
    return null;
}

// Get authenticated Gmail client
async function getGmailClient(email, clientId, clientSecret) {
    const tokens = await getGmailTokens(email);
    if (!tokens) {
        throw new Error(`No Gmail tokens found for ${email}`);
    }
    const oauth2Client = getGmailOAuth2Client(clientId, clientSecret);
    oauth2Client.setCredentials(tokens);
    return google.gmail({ version: 'v1', auth: oauth2Client });
}

// Default email templates
const EMAIL_TEMPLATES = {
    OFF: {
        subject: 'Aurora Viking Tour Update - Tonight\'s Tour Cancelled',
        body: `Dear Northern Lights Hunter,

Unfortunately, we have made the difficult decision to cancel tonight's aurora tour due to unfavorable weather conditions.

We understand this may be disappointing, but the safety and experience quality of our guests is our top priority. These conditions would significantly reduce our chances of aurora sightings.

Your Options:
1. RESCHEDULE: We can move your booking to another night during your stay
2. FULL REFUND: If rescheduling isn't possible, we'll provide a complete refund

Please reply to this email or contact us to let us know your preference.

Thank you for your understanding.

Clear skies,
Aurora Viking Team
📧 info@auroraviking.is
📱 +354 XXX XXXX`
    },
    ON: {
        subject: 'Aurora Viking Tour Update - Tonight\'s Tour is ON! 🌌',
        body: `Dear Northern Lights Hunter,

Great news! Tonight's aurora tour is CONFIRMED and running as scheduled!

Important Reminders:
• Be at your pickup location 10 minutes before the scheduled time
• Dress warmly in layers (thermals, warm jacket, hat, gloves)
• Bring a camera if you'd like to capture the magic

We're excited to take you on this adventure!

Clear skies,
Aurora Viking Team
📧 info@auroraviking.is
📱 +354 XXX XXXX`
    }
};

// Fetch bookings for a specific date from Bokun
async function fetchBookingsForDate(dateString, accessKey, secretKey) {
    const path = '/booking.json/product-booking-search';
    const method = 'POST';

    // Date range for the specific day
    const startOfDay = `${dateString}T00:00:00Z`;
    const endOfDay = `${dateString}T23:59:59Z`;

    const requestBody = JSON.stringify({
        pageSize: 500,
        page: 0,
        filters: {
            startDateRange: {
                from: startOfDay,
                to: endOfDay
            },
            confirmed: true
        }
    });

    const bokunDate = new Date().toISOString().replace(/[-:]/g, '').split('.')[0] + 'Z';
    const signatureString = bokunDate + accessKey + method + path;
    const signature = crypto.createHmac('sha1', secretKey).update(signatureString).digest('base64');

    return new Promise((resolve, reject) => {
        const options = {
            hostname: 'api.bokun.io',
            path,
            method,
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(requestBody),
                'X-Bokun-AccessKey': accessKey,
                'X-Bokun-Date': bokunDate,
                'X-Bokun-Signature': signature,
            },
        };

        const req = https.request(options, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                if (res.statusCode >= 200 && res.statusCode < 300) {
                    try {
                        const result = JSON.parse(data);
                        resolve(result.items || []);
                    } catch (e) {
                        resolve([]);
                    }
                } else {
                    console.log(`Bokun API error: ${res.statusCode}`);
                    resolve([]);
                }
            });
        });

        req.on('error', (e) => {
            console.error('Bokun request error:', e);
            resolve([]);
        });
        req.write(requestBody);
        req.end();
    });
}

// Extract unique customer emails from bookings
function extractCustomerEmails(bookings) {
    const emails = new Set();
    const customerData = [];

    for (const booking of bookings) {
        const customer = booking.customer || booking.contact || {};
        const email = customer.email || customer.emailAddress;

        if (email && !emails.has(email.toLowerCase())) {
            emails.add(email.toLowerCase());
            customerData.push({
                email: email.toLowerCase(),
                name: customer.firstName || customer.name || 'Valued Customer',
                bookingId: booking.id || booking.confirmationCode,
            });
        }
    }

    return customerData;
}


/**
 * Get today's date in YYYY-MM-DD format (Iceland timezone)
 */
function getTodayDateString() {
    const now = new Date();
    // Iceland is UTC+0 year-round
    const icelandDate = new Date(now.toLocaleString('en-US', { timeZone: 'Atlantic/Reykjavik' }));
    return icelandDate.toISOString().split('T')[0];
}

/**
 * Format date for display (e.g., "21.JAN")
 */
function formatDateForDisplay(dateString) {
    const date = new Date(dateString);
    const day = date.getDate();
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    const month = months[date.getMonth()];
    return `${day}.${month}`;
}

/**
 * Check if we're in aurora season (mid-August to end of April)
 */
function isAuroraSeason() {
    const now = new Date();
    const month = now.getMonth() + 1; // 1-12
    const day = now.getDate();

    // Aurora season: August 15 - April 30
    if (month >= 5 && month <= 7) return false; // May, June, July - definitely not
    if (month === 8 && day < 15) return false; // Before August 15
    return true; // August 15+ through April
}

// ============================================
// CLOUD FUNCTIONS
// ============================================

/**
 * Get tour status for today (public endpoint for website widget)
 */
const getTourStatus = onRequest(
    {
        region: 'us-central1',
        cors: true,
    },
    async (req, res) => {
        // Set CORS headers explicitly for Wix compatibility
        res.set('Access-Control-Allow-Origin', '*');
        res.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
        res.set('Access-Control-Allow-Headers', 'Content-Type');

        // Handle preflight
        if (req.method === 'OPTIONS') {
            res.status(204).send('');
            return;
        }

        try {
            // Allow specific date query or default to today
            const dateParam = req.query.date;
            const dateString = dateParam || getTodayDateString();

            console.log(`📅 Getting tour status for: ${dateString}`);

            const statusDoc = await db.collection('tour_status').doc(dateString).get();

            if (!statusDoc.exists) {
                // No status set yet - return unknown
                res.json({
                    date: dateString,
                    displayDate: formatDateForDisplay(dateString),
                    status: 'UNKNOWN',
                    message: 'Status not yet set for today',
                    updatedAt: null,
                });
                return;
            }

            const data = statusDoc.data();

            res.json({
                date: dateString,
                displayDate: formatDateForDisplay(dateString),
                status: data.status,
                message: data.message || '',
                updatedAt: data.updatedAt?.toDate?.() || null,
                updatedByName: data.updatedByName || null,
            });
        } catch (error) {
            console.error('❌ Error getting tour status:', error);
            res.status(500).json({ error: error.message });
        }
    }
);

/**
 * Internal function to send tour status emails
 * Called by both setTourStatus (auto) and sendTourStatusEmails (manual)
 */
async function sendTourStatusEmailsInternal(dateString, status, sentByUid) {
    console.log(`📧 [Internal] Sending ${status} emails for ${dateString}...`);

    const accessKey = process.env.BOKUN_ACCESS_KEY;
    const secretKey = process.env.BOKUN_SECRET_KEY;
    const clientId = process.env.GMAIL_CLIENT_ID;
    const clientSecret = process.env.GMAIL_CLIENT_SECRET;

    if (!accessKey || !secretKey) {
        console.log('⚠️ Bokun keys not available - skipping email send');
        return { success: false, emailsSent: 0, error: 'Bokun keys not configured' };
    }

    if (!clientId || !clientSecret) {
        console.log('⚠️ Gmail keys not available - skipping email send');
        return { success: false, emailsSent: 0, error: 'Gmail keys not configured' };
    }

    try {
        // Fetch bookings from Bokun
        console.log('📋 Fetching bookings for date...');
        const bookings = await fetchBookingsForDate(dateString, accessKey, secretKey);
        console.log(`📋 Found ${bookings.length} bookings`);

        if (bookings.length === 0) {
            return { success: true, emailsSent: 0, message: 'No bookings found' };
        }

        // Extract unique customer emails
        const customers = extractCustomerEmails(bookings);
        console.log(`👥 Found ${customers.length} unique customers`);

        if (customers.length === 0) {
            return { success: true, emailsSent: 0, message: 'No customer emails found' };
        }

        // Get email template
        const template = EMAIL_TEMPLATES[status];
        const templateDoc = await db.collection('email_templates').doc(`tour_${status.toLowerCase()}`).get();
        const customTemplate = templateDoc.exists ? templateDoc.data() : null;

        const emailSubject = customTemplate?.subject || template.subject;
        const emailBody = customTemplate?.body || template.body;

        // Setup Gmail client
        const fromEmail = 'info@auroraviking.is';
        const gmail = await getGmailClient(fromEmail, clientId, clientSecret);

        // Send emails - use BCC for efficiency
        let emailsSent = 0;
        const batchSize = 50;

        for (let i = 0; i < customers.length; i += batchSize) {
            const batch = customers.slice(i, i + batchSize);
            const bccEmails = batch.map(c => c.email);

            console.log(`📤 Sending batch ${Math.floor(i / batchSize) + 1} (${bccEmails.length} recipients)`);

            const emailLines = [
                `From: Aurora Viking <${fromEmail}>`,
                `To: ${fromEmail}`,
                `Bcc: ${bccEmails.join(', ')}`,
                `Subject: ${emailSubject}`,
                'Content-Type: text/plain; charset=utf-8',
                '',
                emailBody,
            ];

            const rawMessage = Buffer.from(emailLines.join('\r\n'))
                .toString('base64')
                .replace(/\+/g, '-')
                .replace(/\//g, '_')
                .replace(/=+$/, '');

            try {
                await gmail.users.messages.send({
                    userId: 'me',
                    requestBody: { raw: rawMessage },
                });
                emailsSent += bccEmails.length;
                console.log(`✅ Batch sent successfully`);
            } catch (sendError) {
                console.error(`❌ Failed to send batch: ${sendError.message}`);
            }
        }

        // Log the email send action
        await db.collection('tour_status_emails').add({
            date: dateString,
            status,
            totalBookings: bookings.length,
            uniqueCustomers: customers.length,
            emailsSent,
            sentAt: admin.firestore.FieldValue.serverTimestamp(),
            sentBy: sentByUid || 'system',
            triggeredBy: 'auto',
        });

        console.log(`✅ Tour status emails complete: ${emailsSent}/${customers.length} sent`);

        return {
            success: true,
            emailsSent,
            bookingsFound: bookings.length,
            uniqueCustomers: customers.length,
        };

    } catch (error) {
        console.error('❌ Error in sendTourStatusEmailsInternal:', error);
        return { success: false, emailsSent: 0, error: error.message };
    }
}

/**
 * Set tour status (admin only) - NOW WITH AUTO EMAIL SENDING
 */
const setTourStatus = onCall(
    {
        region: 'us-central1',
        secrets: ['GMAIL_CLIENT_ID', 'GMAIL_CLIENT_SECRET', 'BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY'],
        timeoutSeconds: 300,
    },
    async (request) => {
        console.log('🔄 Setting tour status...');

        if (!request.auth) {
            throw new Error('You must be logged in to set tour status');
        }

        const uid = request.auth.uid;
        const { date, status, message, sendEmail = true } = request.data;

        if (!status || !['ON', 'OFF'].includes(status)) {
            throw new Error('Status must be "ON" or "OFF"');
        }

        // Use provided date or today
        const dateString = date || getTodayDateString();

        // Get user info for logging
        let userName = 'Unknown';
        try {
            const userDoc = await db.collection('users').doc(uid).get();
            if (userDoc.exists) {
                userName = userDoc.data().fullName || userDoc.data().email || 'Unknown';
            }
        } catch (e) {
            console.log('Could not get user name:', e.message);
        }

        const statusData = {
            date: dateString,
            status: status,
            message: message || '',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedBy: uid,
            updatedByName: userName,
        };

        await db.collection('tour_status').doc(dateString).set(statusData);

        console.log(`✅ Tour status set: ${dateString} = ${status} by ${userName}`);

        // Also log to history
        await db.collection('tour_status_history').add({
            ...statusData,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // AUTO-SEND EMAILS when status is set
        let emailResult = { emailsSent: 0 };
        if (sendEmail) {
            console.log(`📧 Auto-sending ${status} emails to customers...`);
            emailResult = await sendTourStatusEmailsInternal(dateString, status, uid);
            console.log(`📧 Email result: ${emailResult.emailsSent} sent`);
        }

        return {
            success: true,
            date: dateString,
            displayDate: formatDateForDisplay(dateString),
            status: status,
            message: message || '',
            updatedByName: userName,
            emailsSent: emailResult.emailsSent || 0,
            emailError: emailResult.error || null,
        };
    }
);

/**
 * Get tour status history (admin only)
 */
const getTourStatusHistory = onCall(
    {
        region: 'us-central1',
    },
    async (request) => {
        if (!request.auth) {
            throw new Error('You must be logged in');
        }

        const { limit = 14 } = request.data || {};

        // Get last N days of status
        const snapshot = await db.collection('tour_status')
            .orderBy('date', 'desc')
            .limit(limit)
            .get();

        const history = snapshot.docs.map(doc => ({
            date: doc.id,
            displayDate: formatDateForDisplay(doc.id),
            ...doc.data(),
            updatedAt: doc.data().updatedAt?.toDate?.() || null,
        }));

        return { history };
    }
);

/**
 * Daily reminder notification at 15:00 Iceland time
 * Runs during aurora season (August 15 - April 30)
 */
const tourStatusReminder = onSchedule(
    {
        schedule: '0 15 * * *', // 15:00 UTC (Iceland time)
        region: 'us-central1',
        timeZone: 'Atlantic/Reykjavik',
    },
    async () => {
        console.log('⏰ Tour status reminder triggered');

        // Check if we're in aurora season
        if (!isAuroraSeason()) {
            console.log('☀️ Not in aurora season, skipping reminder');
            return;
        }

        const today = getTodayDateString();

        // Check if status is already set for today
        const statusDoc = await db.collection('tour_status').doc(today).get();

        if (statusDoc.exists) {
            console.log(`✅ Status already set for ${today}: ${statusDoc.data().status}`);
            return; // Already set, no reminder needed
        }

        // Send reminder notification to admins
        console.log('📤 Sending tour status reminder to admins...');

        await sendNotificationToAdminsOnly(
            '🌌 Is tonight\'s tour running?',
            'Tap to set today\'s tour status to ON or OFF',
            {
                type: 'tour_status_reminder',
                date: today,
                action: 'set_tour_status',
            }
        );

        console.log('✅ Tour status reminder sent');
    }
);

/**
 * Send tour status emails to all customers with bookings for a specific date
 */
const sendTourStatusEmails = onCall(
    {
        region: 'us-central1',
        secrets: ['GMAIL_CLIENT_ID', 'GMAIL_CLIENT_SECRET', 'BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY'],
        timeoutSeconds: 300,
    },
    async (request) => {
        console.log('📧 Sending tour status emails...');

        if (!request.auth) {
            throw new Error('You must be logged in to send tour status emails');
        }

        const { date, status } = request.data;

        if (!status || !['ON', 'OFF'].includes(status)) {
            throw new Error('Status must be "ON" or "OFF"');
        }

        const dateString = date || getTodayDateString();
        console.log(`📅 Processing emails for: ${dateString}, Status: ${status}`);

        try {
            // Fetch bookings from Bokun
            const accessKey = process.env.BOKUN_ACCESS_KEY;
            const secretKey = process.env.BOKUN_SECRET_KEY;

            console.log('📋 Fetching bookings for date...');
            const bookings = await fetchBookingsForDate(dateString, accessKey, secretKey);
            console.log(`📋 Found ${bookings.length} bookings for ${dateString}`);

            if (bookings.length === 0) {
                return {
                    success: true,
                    message: 'No bookings found for this date',
                    emailsSent: 0,
                };
            }

            // Extract unique customer emails
            const customers = extractCustomerEmails(bookings);
            console.log(`👥 Found ${customers.length} unique customers`);

            if (customers.length === 0) {
                return {
                    success: true,
                    message: 'No customer emails found',
                    emailsSent: 0,
                };
            }

            // Get email template
            const template = EMAIL_TEMPLATES[status];

            // Check for custom template in Firestore
            const templateDoc = await db.collection('email_templates').doc(`tour_${status.toLowerCase()}`).get();
            const customTemplate = templateDoc.exists ? templateDoc.data() : null;

            const emailSubject = customTemplate?.subject || template.subject;
            const emailBody = customTemplate?.body || template.body;

            // Setup Gmail client
            const clientId = process.env.GMAIL_CLIENT_ID;
            const clientSecret = process.env.GMAIL_CLIENT_SECRET;
            const fromEmail = 'info@auroraviking.is';

            const gmail = await getGmailClient(fromEmail, clientId, clientSecret);

            // Send emails - use BCC for efficiency
            let emailsSent = 0;
            const batchSize = 50; // Gmail BCC limit per email

            for (let i = 0; i < customers.length; i += batchSize) {
                const batch = customers.slice(i, i + batchSize);
                const bccEmails = batch.map(c => c.email);

                console.log(`📤 Sending batch ${Math.floor(i / batchSize) + 1} (${bccEmails.length} recipients)`);

                // Build email with BCC
                const emailLines = [
                    `From: Aurora Viking <${fromEmail}>`,
                    `To: ${fromEmail}`, // Send to ourselves, BCC the customers
                    `Bcc: ${bccEmails.join(', ')}`,
                    `Subject: ${emailSubject}`,
                    'Content-Type: text/plain; charset=utf-8',
                    '',
                    emailBody,
                ];

                const rawMessage = Buffer.from(emailLines.join('\r\n'))
                    .toString('base64')
                    .replace(/\+/g, '-')
                    .replace(/\//g, '_')
                    .replace(/=+$/, '');

                try {
                    await gmail.users.messages.send({
                        userId: 'me',
                        requestBody: {
                            raw: rawMessage,
                        },
                    });
                    emailsSent += bccEmails.length;
                    console.log(`✅ Batch sent successfully`);
                } catch (sendError) {
                    console.error(`❌ Failed to send batch: ${sendError.message}`);
                }
            }

            // Log the email send action
            await db.collection('tour_status_emails').add({
                date: dateString,
                status,
                totalBookings: bookings.length,
                uniqueCustomers: customers.length,
                emailsSent,
                sentAt: admin.firestore.FieldValue.serverTimestamp(),
                sentBy: request.auth.uid,
            });

            console.log(`✅ Tour status emails complete: ${emailsSent}/${customers.length} sent`);

            return {
                success: true,
                date: dateString,
                status,
                bookingsFound: bookings.length,
                uniqueCustomers: customers.length,
                emailsSent,
            };

        } catch (error) {
            console.error('❌ Error sending tour status emails:', error);
            throw new Error(`Failed to send emails: ${error.message}`);
        }
    }
);

module.exports = {
    getTourStatus,
    setTourStatus,
    getTourStatusHistory,
    tourStatusReminder,
    sendTourStatusEmails,
};
