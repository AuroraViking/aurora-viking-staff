/**
 * Guide Shift SMS Reminder
 * Sends SMS to active guides 36h before departure asking them to apply for shifts.
 * 
 * - Runs every hour via Cloud Scheduler
 * - Only contacts guides with isActive=true AND smsEnabled=true
 * - Checks if bookings exist for the target date
 * - Avoids duplicate sends via Firestore log
 */
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall } = require('firebase-functions/v2/https');
const { admin, db } = require('../utils/firebase');

// Twilio client (lazy-init, reuse pattern from sms.js)
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
 * Get the date string for 36 hours from now (Iceland timezone)
 */
function getTargetDateStr() {
    const now = new Date();
    const future = new Date(now.getTime() + 36 * 60 * 60 * 1000);
    const iceland = new Date(future.toLocaleString('en-US', { timeZone: 'Atlantic/Reykjavik' }));
    return `${iceland.getFullYear()}-${String(iceland.getMonth() + 1).padStart(2, '0')}-${String(iceland.getDate()).padStart(2, '0')}`;
}

/**
 * Get today's date in Iceland timezone
 */
function getTodayStr() {
    const now = new Date();
    const iceland = new Date(now.toLocaleString('en-US', { timeZone: 'Atlantic/Reykjavik' }));
    return `${iceland.getFullYear()}-${String(iceland.getMonth() + 1).padStart(2, '0')}-${String(iceland.getDate()).padStart(2, '0')}`;
}

/**
 * Check if there are bookings for the target date
 */
async function hasBookingsForDate(dateStr) {
    const cachedDoc = await db.collection('cached_bookings').doc(dateStr).get();
    if (cachedDoc.exists) {
        const data = cachedDoc.data();
        const bookings = data.bookings || [];
        if (bookings.length > 0) return true;
    }
    // Also check manual bookings
    const manualSnap = await db.collection('manual_bookings')
        .where('date', '==', dateStr)
        .limit(1)
        .get();
    return !manualSnap.empty;
}

/**
 * Get active guides with SMS enabled and a phone number
 */
async function getEligibleGuides() {
    const guidesSnap = await db.collection('users')
        .where('role', 'in', ['guide', 'admin'])
        .where('isActive', '==', true)
        .get();

    return guidesSnap.docs
        .map(doc => ({ id: doc.id, ...doc.data() }))
        .filter(guide => {
            // Must have smsEnabled (defaults to true if not set)
            const smsEnabled = guide.smsEnabled !== false;
            // Must have a phone number
            const phone = (guide.phoneNumber || '').trim();
            return smsEnabled && phone.length > 0 && phone.startsWith('+');
        });
}

/**
 * Check if we already sent a reminder for this date
 */
async function alreadySentReminder(dateStr) {
    const logDoc = await db.collection('guide_sms_log').doc(`shift_reminder_${dateStr}`).get();
    return logDoc.exists;
}

/**
 * Send shift reminder SMS to eligible guides
 */
async function sendShiftReminders(dateStr) {
    console.log(`📱 Checking shift reminder SMS for ${dateStr}...`);

    // Already sent?
    if (await alreadySentReminder(dateStr)) {
        console.log(`⏭️ Reminder already sent for ${dateStr}`);
        return { action: 'already_sent', date: dateStr };
    }

    // Any bookings?
    if (!(await hasBookingsForDate(dateStr))) {
        console.log(`📭 No bookings for ${dateStr}, skipping SMS`);
        return { action: 'no_bookings', date: dateStr };
    }

    // Get eligible guides
    const guides = await getEligibleGuides();
    console.log(`👥 Found ${guides.length} eligible guides for SMS`);

    if (guides.length === 0) {
        return { action: 'no_eligible_guides', date: dateStr };
    }

    // Check how many have already applied for this date
    const dateObj = new Date(dateStr + 'T00:00:00');
    const nextDay = new Date(dateStr + 'T23:59:59');
    const shiftsSnap = await db.collection('shifts')
        .where('date', '>=', dateObj.toISOString())
        .where('date', '<=', nextDay.toISOString())
        .get();

    // Also check plain date format
    const shiftsPlainSnap = await db.collection('shifts')
        .where('date', '==', dateStr)
        .get();

    const appliedGuideIds = new Set();
    [...shiftsSnap.docs, ...shiftsPlainSnap.docs].forEach(doc => {
        const d = doc.data();
        if (d.guideId) appliedGuideIds.add(d.guideId);
    });

    // Only SMS guides who haven't applied yet
    const guidesToNotify = guides.filter(g => !appliedGuideIds.has(g.id));
    console.log(`📲 ${guidesToNotify.length} guides haven't applied yet (${appliedGuideIds.size} already applied)`);

    if (guidesToNotify.length === 0) {
        // Log that all guides already applied
        await db.collection('guide_sms_log').doc(`shift_reminder_${dateStr}`).set({
            date: dateStr,
            sentAt: admin.firestore.FieldValue.serverTimestamp(),
            totalGuides: guides.length,
            alreadyApplied: appliedGuideIds.size,
            smsSent: 0,
            message: 'All eligible guides already applied',
        });
        return { action: 'all_applied', date: dateStr };
    }

    // Send SMS
    const client = getTwilioClient();
    const messagingServiceSid = process.env.TWILIO_MESSAGING_SERVICE_SID;
    const fromNumber = process.env.TWILIO_PHONE_NUMBER;

    if (!messagingServiceSid && !fromNumber) {
        console.log('⚠️ No Twilio sender configured');
        return { action: 'no_twilio_sender', date: dateStr };
    }

    // Format the date nicely
    const dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    const targetDate = new Date(dateStr + 'T12:00:00');
    const dayName = dayNames[targetDate.getDay()];
    const formattedDate = `${dayName} ${dateStr}`;

    let smsSent = 0;
    const failed = [];

    for (const guide of guidesToNotify) {
        const firstName = (guide.fullName || guide.displayName || 'Guide').split(' ')[0];
        const phone = guide.phoneNumber.trim();

        const body = `Hi ${firstName}! 🌌 We have bookings for ${formattedDate}. Open the Aurora Viking app to apply for the shift! — Aurora Viking`;

        try {
            const opts = { body, to: phone };
            if (messagingServiceSid) {
                opts.messagingServiceSid = messagingServiceSid;
            } else {
                opts.from = fromNumber;
            }

            await client.messages.create(opts);
            smsSent++;
            console.log(`✅ Shift SMS sent to ${firstName} (${phone})`);
        } catch (err) {
            console.error(`❌ Failed SMS to ${phone}: ${err.message}`);
            failed.push({ phone, error: err.message });
        }

        // Rate limit
        if (guidesToNotify.length > 3) {
            await new Promise(r => setTimeout(r, 300));
        }
    }

    // Log the send
    await db.collection('guide_sms_log').doc(`shift_reminder_${dateStr}`).set({
        date: dateStr,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        totalGuides: guides.length,
        alreadyApplied: appliedGuideIds.size,
        smsSent,
        failed,
        guidesNotified: guidesToNotify.map(g => ({ id: g.id, name: g.fullName || g.displayName })),
    });

    console.log(`✅ Shift reminder complete: ${smsSent}/${guidesToNotify.length} sent for ${dateStr}`);

    return { action: 'sent', date: dateStr, smsSent, total: guidesToNotify.length };
}

// ============================================
// EXPORTED CLOUD FUNCTIONS
// ============================================

/**
 * Scheduled: Run every hour to check if 36h reminder needs to go out
 */
const guideShiftReminderScheduled = onSchedule(
    {
        schedule: 'every 1 hours',
        timeZone: 'Atlantic/Reykjavik',
        region: 'us-central1',
        secrets: ['TWILIO_ACCOUNT_SID', 'TWILIO_AUTH_TOKEN', 'TWILIO_MESSAGING_SERVICE_SID'],
    },
    async () => {
        console.log('📱 Scheduled guide shift reminder check...');
        try {
            const targetDate = getTargetDateStr();
            const result = await sendShiftReminders(targetDate);
            console.log('📱 Shift reminder result:', JSON.stringify(result));
            return result;
        } catch (error) {
            console.error('❌ Guide shift reminder failed:', error);
            return null;
        }
    }
);

/**
 * Manual trigger for testing
 */
const guideShiftReminderManual = onCall(
    {
        region: 'us-central1',
        secrets: ['TWILIO_ACCOUNT_SID', 'TWILIO_AUTH_TOKEN', 'TWILIO_MESSAGING_SERVICE_SID'],
    },
    async (request) => {
        if (!request.auth) {
            throw new Error('Authentication required');
        }

        const dateStr = request.data?.date || getTargetDateStr();
        console.log(`📱 Manual shift reminder for ${dateStr} by ${request.auth.uid}`);
        return await sendShiftReminders(dateStr);
    }
);

module.exports = {
    guideShiftReminderScheduled,
    guideShiftReminderManual,
};
