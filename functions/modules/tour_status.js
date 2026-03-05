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
    // Firestore stores camelCase, OAuth expects snake_case
    oauth2Client.setCredentials({
        access_token: tokens.accessToken || tokens.access_token,
        refresh_token: tokens.refreshToken || tokens.refresh_token,
        expiry_date: tokens.expiryDate || tokens.expiry_date,
    });
    return google.gmail({ version: 'v1', auth: oauth2Client });
}

// Forecast URL for cancellation emails
const FORECAST_URL = 'https://www.weatherandradar.com/weather-map/reykjavik/14773115?layer=wr&center=64.1355,-21.8954&placemark=64.1355,-21.8954';

// Build HTML OFF (cancellation) email
function buildOffEmailHtml(firstName, confirmationCode, email, fullName) {
    let portalUrl = 'https://www.auroraviking.com/bookings';
    const params = [];
    if (confirmationCode) params.push(`code=${encodeURIComponent(confirmationCode)}`);
    if (email) params.push(`email=${encodeURIComponent(email)}`);
    if (fullName) params.push(`name=${encodeURIComponent(fullName)}`);
    if (params.length > 0) portalUrl += '?' + params.join('&');

    return `<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#1a1a2e;font-family:Arial,Helvetica,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#1a1a2e;padding:20px 0;">
<tr><td align="center">
<table width="600" cellpadding="0" cellspacing="0" style="background:#16213e;border-radius:12px;overflow:hidden;max-width:100%;">
  <tr><td style="background:linear-gradient(135deg,#0f3460,#533483);padding:30px;text-align:center;">
    <h1 style="color:#e94560;margin:0;font-size:22px;letter-spacing:1px;">AURORA VIKING</h1>
    <p style="color:#ccc;margin:8px 0 0;font-size:13px;">Tour Status Update</p>
  </td></tr>
  <tr><td style="padding:30px;color:#e0e0e0;font-size:15px;line-height:1.7;">
    <p>Hello ${firstName || 'everyone'}!</p>
    <p><strong style="color:#e94560;font-size:17px;">The Northern Lights tour tonight is cancelled.</strong></p>
    <p>Unfortunately the cloud cover forecast is not favorable tonight giving us slim chances of being able to find clear skies to observe the Northern Lights. Of course the forecast could be wrong but we usually don't bet against the forecast.</p>
    <p>You can see the forecast by clicking this link: <a href="${FORECAST_URL}" style="color:#4fc3f7;text-decoration:underline;font-weight:bold;">THE FORECAST</a><br>
    <span style="color:#aaa;font-size:13px;">The white color represents clouds while blue represents rain and pink snow.</span></p>
    <p>Please let us know what you want to do, if you want to reschedule or otherwise, we need to hear from you so we don't have to worry that you didn't receive this message and will be waiting for us to show up tonight when we aren't going to be.</p>
    <p>Click the button below to reschedule or cancel your booking. If you have any issues, email us at <a href="mailto:info@auroraviking.com" style="color:#4fc3f7;">info@auroraviking.com</a> with your decision asap.</p>
    <div style="text-align:center;margin:25px 0;">
      <a href="${portalUrl}" style="display:inline-block;background:linear-gradient(135deg,#00b894,#00cec9);color:#fff;text-decoration:none;padding:14px 32px;border-radius:8px;font-weight:bold;font-size:16px;letter-spacing:0.5px;">Go to Booking Portal</a>
      <p style="color:#aaa;font-size:13px;margin-top:12px;">Your booking reference is: <strong style="color:#e0e0e0;font-size:14px;">${confirmationCode || 'N/A'}</strong><br>Enter it in the Booking Portal if prompted.</p>
    </div>
    <p>All the best and fingers crossed for better conditions.<br>
    <strong>Kobe and Emil.</strong></p>
  </td></tr>
  <tr><td style="background:#0f3460;padding:20px;text-align:center;color:#888;font-size:12px;">
    Aurora Viking &bull; <a href="mailto:info@auroraviking.com" style="color:#4fc3f7;">info@auroraviking.com</a> &bull; +354 784 4000
  </td></tr>
</table>
</td></tr></table>
</body></html>`;
}

// Build HTML ON (confirmation) email with pickup info
function buildOnEmailHtml(firstName, pickupLocation, startTime) {
    return `<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#1a1a2e;font-family:Arial,Helvetica,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#1a1a2e;padding:20px 0;">
<tr><td align="center">
<table width="600" cellpadding="0" cellspacing="0" style="background:#16213e;border-radius:12px;overflow:hidden;max-width:100%;">
  <tr><td style="background:linear-gradient(135deg,#0f3460,#1b4332);padding:30px;text-align:center;">
    <h1 style="color:#00b894;margin:0;font-size:22px;letter-spacing:1px;">AURORA VIKING</h1>
    <p style="color:#ccc;margin:8px 0 0;font-size:13px;">Tour Confirmation</p>
  </td></tr>
  <tr><td style="padding:30px;color:#e0e0e0;font-size:15px;line-height:1.7;">
    <p>Hi ${firstName || 'there'},</p>
    <p><strong style="color:#00b894;font-size:18px;">THE TOUR IS ON TONIGHT! 🌌</strong></p>
    ${pickupLocation ? `
    <div style="background:#1a1a2e;border-left:4px solid #00b894;padding:15px 20px;margin:15px 0;border-radius:0 8px 8px 0;">
      <p style="margin:0 0 5px;color:#00b894;font-weight:bold;font-size:13px;">YOUR PICKUP DETAILS</p>
      <p style="margin:0;font-size:15px;">📍 <strong>${pickupLocation}</strong></p>
      ${startTime ? `<p style="margin:5px 0 0;font-size:15px;">🕐 Be ready at <strong>${startTime}</strong></p>` : ''}
    </div>` : ''}
    <p>The pickup can last up to half an hour and it starts at ${startTime || 'the scheduled time'}. That means you have to be ready at your pickup${pickupLocation ? ` (${pickupLocation})` : ''} at ${startTime || 'the scheduled time'} but if you are not the first pickup you might have to wait a few minutes.</p>
    <p>So if the bus isn't there at ${startTime || 'the scheduled time'} <strong>don't panic</strong> :) Most likely you are not the first pickup and you might have to wait a few minutes for it to arrive.</p>
    <p><strong style="color:#e94560;">DRESS WELL.</strong> If you get cold waiting outside for a few minutes you might not be dressed to stand outside looking at the northern lights. You have travelled to ICE-land so yes it can get really cold.</p>
    <p>Our minibuses are white with a black <strong>"AURORA VIKING"</strong> logo on the side. We sometimes lease other buses so just listen for your name being called.</p>
    <p>If your guide does not spot you at the pick up location he might jump out of the minibus and bellow your name, like a true Viking, usually causing fear and dismay amongst the people waiting for their pick ups. <em>Do not be alarmed.</em></p>
    <p>If we can't find you at your pick up location we will call and send an email, if you don't reply or answer within 3 minutes we will be assuming that you can't make it on the tour and continue with the pick up.</p>
    <p><strong>Make sure you use the bathroom before you head to the pick up location.</strong> Access to toilets can be limited during the tour.</p>
    <p style="color:#aaa;font-size:13px;">You can find your pickup location on Google Maps (for example write "Bus stop 1" for that pickup etc) but note that if your pickup is at Bus stop 8 you can write "Hallgrimstorg" for the exact location. If your pickup location is at Bus stop 15 or Bus stop 17 then if you look up "Maritime Museum" on Google Maps you'll find it.</p>
  </td></tr>
  <tr><td style="background:#0f3460;padding:20px;text-align:center;color:#888;font-size:12px;line-height:1.6;">
    <strong style="color:#e0e0e0;">Having problems with your pickup?</strong><br>
    Email: <a href="mailto:info@auroraviking.com" style="color:#4fc3f7;">info@auroraviking.com</a> (we reply promptly around pickup time)<br>
    Call: <strong style="color:#e0e0e0;">+354 784 4000</strong>
  </td></tr>
</table>
</td></tr></table>
</body></html>`;
}

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

// Extract customer data from cached bookings (supports both cached and Bokun formats)
function extractCustomerData(bookings) {
    const emails = new Set();
    const customerData = [];

    for (const booking of bookings) {
        // Support cached_bookings fields (flat) and Bokun API fields (nested)
        const email = booking.email ||
            booking.customer?.email ||
            booking.customer?.emailAddress ||
            booking.contact?.email;

        if (!email || emails.has(email.toLowerCase())) continue;
        emails.add(email.toLowerCase());

        // Extract first name
        const fullName = booking.customerFullName ||
            ((booking.customer?.firstName || '') + ' ' + (booking.customer?.lastName || '')).trim() ||
            'Valued Customer';
        const firstName = fullName.split(' ')[0] || 'there';

        // Extract pickup info (from cached_bookings)
        const pickupLocation = booking.pickupPlaceName || '';
        const departureTime = booking.departureTime || '';
        const confirmationCode = booking.confirmationCode || '';

        customerData.push({
            email: email.toLowerCase(),
            firstName,
            fullName,
            pickupLocation,
            departureTime,
            confirmationCode,
            bookingId: booking.bookingId || booking.id || confirmationCode,
        });
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
 * Now uses cached_bookings (same as pickup menu) and sends individual personalized HTML emails
 */
async function sendTourStatusEmailsInternal(dateString, status, sentByUid) {
    console.log(`📧 [Internal] Sending ${status} emails for ${dateString}...`);

    const clientId = process.env.GMAIL_CLIENT_ID;
    const clientSecret = process.env.GMAIL_CLIENT_SECRET;

    if (!clientId || !clientSecret) {
        console.log('⚠️ Gmail keys not available - skipping email send');
        return { success: false, emailsSent: 0, error: 'Gmail keys not configured' };
    }

    try {
        // Fetch bookings from cached_bookings (same source as pickup menu)
        console.log('📋 Fetching cached bookings for date...');
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
            return { success: true, emailsSent: 0, message: 'No bookings found' };
        }

        // Extract customer data with pickup info
        const customers = extractCustomerData(bookings);
        console.log(`👥 Found ${customers.length} unique customers with emails`);

        if (customers.length === 0) {
            return { success: true, emailsSent: 0, message: 'No customer emails found' };
        }

        // Setup Gmail client
        const fromEmail = 'info@auroraviking.com';
        const gmail = await getGmailClient(fromEmail, clientId, clientSecret);

        // Email subject lines
        const subject = status === 'OFF'
            ? 'Aurora Viking - Tonight\'s Tour Cancelled'
            : 'Aurora Viking - Tonight\'s Tour is ON! 🌌';

        // Send individual personalized emails
        let emailsSent = 0;
        const failedEmails = [];

        for (const customer of customers) {
            // Build personalized HTML body
            const htmlBody = status === 'OFF'
                ? buildOffEmailHtml(customer.firstName, customer.confirmationCode, customer.email, customer.fullName)
                : buildOnEmailHtml(customer.firstName, customer.pickupLocation, customer.departureTime);

            // Build MIME email
            const emailLines = [
                `From: Aurora Viking <${fromEmail}>`,
                `To: ${customer.email}`,
                `Subject: ${subject}`,
                'MIME-Version: 1.0',
                'Content-Type: text/html; charset=utf-8',
                '',
                htmlBody,
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
                emailsSent++;
                console.log(`✅ Sent to ${customer.firstName} (${customer.email})`);
            } catch (sendError) {
                console.error(`❌ Failed to send to ${customer.email}: ${sendError.message}`);
                failedEmails.push(customer.email);
            }

            // Small delay to avoid Gmail rate limits
            if (customers.length > 5) {
                await new Promise(resolve => setTimeout(resolve, 500));
            }
        }

        // Log the email send action
        await db.collection('tour_status_emails').add({
            date: dateString,
            status,
            totalBookings: bookings.length,
            uniqueCustomers: customers.length,
            emailsSent,
            failedEmails,
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
            failedCount: failedEmails.length,
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
        secrets: ['GMAIL_CLIENT_ID', 'GMAIL_CLIENT_SECRET'],
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
 * Now delegates to sendTourStatusEmailsInternal which uses cached_bookings
 */
const sendTourStatusEmails = onCall(
    {
        region: 'us-central1',
        secrets: ['GMAIL_CLIENT_ID', 'GMAIL_CLIENT_SECRET'],
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
            const result = await sendTourStatusEmailsInternal(dateString, status, request.auth.uid);

            if (!result.success) {
                throw new Error(result.error || 'Failed to send emails');
            }

            return {
                success: true,
                date: dateString,
                status,
                ...result,
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
