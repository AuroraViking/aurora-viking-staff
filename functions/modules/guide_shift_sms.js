/**
 * Guide Shift SMS Reminder — UNDERSTAFFING ONLY
 * 
 * Only sends SMS when we don't have enough guides applied for the bookings.
 * 
 * Triggers:
 * 1. 36h before departure: if guidesNeeded > guidesApplied, SMS unapplied guides
 * 2. Noon same day: second chance if still understaffed
 * 
 * Formula: guidesNeeded = ceil(totalPassengers / 18)
 */
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall } = require('firebase-functions/v2/https');
const { admin, db } = require('../utils/firebase');

// Twilio client (lazy-init)
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
 * Get date string for 36 hours from now (Iceland timezone)
 */
function get36hDateStr() {
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
 * Get current hour in Iceland timezone
 */
function getIcelandHour() {
    const now = new Date();
    const iceland = new Date(now.toLocaleString('en-US', { timeZone: 'Atlantic/Reykjavik' }));
    return iceland.getHours();
}

/**
 * Count total passengers for a date from cached + manual bookings
 */
async function getTotalPassengers(dateStr) {
    let totalPax = 0;

    // Cached bookings
    const cachedDoc = await db.collection('cached_bookings').doc(dateStr).get();
    if (cachedDoc.exists) {
        const bookings = cachedDoc.data().bookings || [];
        for (const b of bookings) {
            totalPax += (b.numberOfGuests || b.guests || b.pax || 1);
        }
    }

    // Manual bookings
    const manualSnap = await db.collection('manual_bookings')
        .where('date', '==', dateStr)
        .get();
    for (const doc of manualSnap.docs) {
        const booking = doc.data().booking || doc.data();
        totalPax += (booking.numberOfGuests || booking.guests || booking.pax || 1);
    }

    return totalPax;
}

/**
 * Calculate guides needed: ceil(passengers / 18)
 */
function guidesNeeded(totalPax) {
    if (totalPax <= 0) return 0;
    return Math.ceil(totalPax / 18);
}

/**
 * Get guide IDs who have already applied/accepted shifts for a date
 */
async function getAppliedGuideIds(dateStr) {
    const appliedIds = new Set();

    // ISO date range query
    const dateObj = new Date(dateStr + 'T00:00:00');
    const nextDay = new Date(dateStr + 'T23:59:59');
    const shiftsSnap = await db.collection('shifts')
        .where('date', '>=', dateObj.toISOString())
        .where('date', '<=', nextDay.toISOString())
        .get();

    // Plain date string query
    const shiftsPlainSnap = await db.collection('shifts')
        .where('date', '==', dateStr)
        .get();

    [...shiftsSnap.docs, ...shiftsPlainSnap.docs].forEach(doc => {
        const d = doc.data();
        if (d.guideId) appliedIds.add(d.guideId);
    });

    return appliedIds;
}

/**
 * Get active guides with SMS enabled and a valid phone number
 */
async function getEligibleGuides() {
    const guidesSnap = await db.collection('users')
        .where('role', 'in', ['guide', 'admin'])
        .where('isActive', '==', true)
        .get();

    return guidesSnap.docs
        .map(doc => ({ id: doc.id, ...doc.data() }))
        .filter(guide => {
            const smsEnabled = guide.smsEnabled !== false;
            const phone = (guide.phoneNumber || '').trim();
            return smsEnabled && phone.length > 0 && phone.startsWith('+');
        });
}

/**
 * Core function: check understaffing and send SMS if needed
 * @param {string} dateStr - target date
 * @param {string} trigger - '36h' or 'noon'
 */
async function checkAndSendIfUnderstaffed(dateStr, trigger) {
    const logKey = `shift_${trigger}_${dateStr}`;
    console.log(`📱 [${trigger}] Checking understaffing for ${dateStr}...`);

    // Already sent for this trigger+date?
    const logDoc = await db.collection('guide_sms_log').doc(logKey).get();
    if (logDoc.exists) {
        console.log(`⏭️ [${trigger}] Already processed for ${dateStr}`);
        return { action: 'already_processed', trigger, date: dateStr };
    }

    // Count passengers
    const totalPax = await getTotalPassengers(dateStr);
    const needed = guidesNeeded(totalPax);
    console.log(`👥 ${totalPax} passengers → ${needed} guides needed`);

    if (needed === 0) {
        console.log(`📭 No bookings for ${dateStr}`);
        return { action: 'no_bookings', trigger, date: dateStr };
    }

    // Count applied guides
    const appliedIds = await getAppliedGuideIds(dateStr);
    const applied = appliedIds.size;
    console.log(`✅ ${applied} guides already applied`);

    // Enough guides? No SMS needed
    if (applied >= needed) {
        console.log(`👍 Enough guides (${applied}/${needed}), no SMS needed`);
        await db.collection('guide_sms_log').doc(logKey).set({
            date: dateStr,
            trigger,
            sentAt: admin.firestore.FieldValue.serverTimestamp(),
            totalPax,
            guidesNeeded: needed,
            guidesApplied: applied,
            smsSent: 0,
            message: 'Enough guides applied, no SMS sent',
        });
        return { action: 'fully_staffed', trigger, date: dateStr, needed, applied };
    }

    // UNDERSTAFFED — send SMS to unapplied guides
    const shortage = needed - applied;
    console.log(`⚠️ UNDERSTAFFED: need ${shortage} more guide(s)`);

    const allGuides = await getEligibleGuides();
    const guidesToNotify = allGuides.filter(g => !appliedIds.has(g.id));

    if (guidesToNotify.length === 0) {
        await db.collection('guide_sms_log').doc(logKey).set({
            date: dateStr,
            trigger,
            sentAt: admin.firestore.FieldValue.serverTimestamp(),
            totalPax,
            guidesNeeded: needed,
            guidesApplied: applied,
            smsSent: 0,
            message: 'Understaffed but no eligible guides to notify',
        });
        return { action: 'no_eligible_guides', trigger, date: dateStr, shortage };
    }

    // Send SMS
    const client = getTwilioClient();
    const messagingServiceSid = process.env.TWILIO_MESSAGING_SERVICE_SID;
    const fromNumber = process.env.TWILIO_PHONE_NUMBER;

    if (!messagingServiceSid && !fromNumber) {
        return { action: 'no_twilio_sender', trigger, date: dateStr };
    }

    const dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    const targetDate = new Date(dateStr + 'T12:00:00');
    const dayName = dayNames[targetDate.getDay()];
    const formattedDate = `${dayName} ${dateStr}`;

    const urgency = trigger === 'noon' ? '⚠️ URGENT: ' : '';

    let smsSent = 0;
    const failed = [];

    for (const guide of guidesToNotify) {
        const firstName = (guide.fullName || guide.displayName || 'Guide').split(' ')[0];
        const phone = guide.phoneNumber.trim();

        const body = `${urgency}Hi ${firstName}! 🌌 We need ${shortage} more guide${shortage > 1 ? 's' : ''} for ${formattedDate} (${totalPax} passengers). Click here to apply: https://auroraviking.com/staff — Aurora Viking`;

        try {
            const opts = { body, to: phone };
            if (messagingServiceSid) {
                opts.messagingServiceSid = messagingServiceSid;
            } else {
                opts.from = fromNumber;
            }

            await client.messages.create(opts);
            smsSent++;
            console.log(`✅ SMS sent to ${firstName} (${phone})`);
        } catch (err) {
            console.error(`❌ Failed SMS to ${phone}: ${err.message}`);
            failed.push({ phone, error: err.message });
        }

        if (guidesToNotify.length > 3) {
            await new Promise(r => setTimeout(r, 300));
        }
    }

    // Log
    await db.collection('guide_sms_log').doc(logKey).set({
        date: dateStr,
        trigger,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        totalPax,
        guidesNeeded: needed,
        guidesApplied: applied,
        shortage,
        smsSent,
        failed,
        guidesNotified: guidesToNotify.map(g => ({ id: g.id, name: g.fullName || g.displayName })),
    });

    console.log(`✅ [${trigger}] SMS complete: ${smsSent}/${guidesToNotify.length} sent (short ${shortage} guides)`);

    return { action: 'sent', trigger, date: dateStr, smsSent, shortage, needed, applied };
}

// ============================================
// EXPORTED CLOUD FUNCTIONS
// ============================================

/**
 * Scheduled: Run every hour
 * - Checks 36h ahead for understaffing
 * - At noon, also checks today for understaffing (second chance)
 */
const guideShiftReminderScheduled = onSchedule(
    {
        schedule: 'every 1 hours',
        timeZone: 'Atlantic/Reykjavik',
        region: 'us-central1',
        secrets: ['TWILIO_ACCOUNT_SID', 'TWILIO_AUTH_TOKEN', 'TWILIO_MESSAGING_SERVICE_SID'],
    },
    async () => {
        console.log('📱 Scheduled understaffing SMS check...');
        const results = [];

        try {
            // 36h ahead check
            const targetDate = get36hDateStr();
            const result36h = await checkAndSendIfUnderstaffed(targetDate, '36h');
            results.push(result36h);
            console.log('📱 36h result:', JSON.stringify(result36h));

            // Noon check for today
            const hour = getIcelandHour();
            if (hour === 12) {
                const today = getTodayStr();
                const resultNoon = await checkAndSendIfUnderstaffed(today, 'noon');
                results.push(resultNoon);
                console.log('📱 Noon result:', JSON.stringify(resultNoon));
            }

            return results;
        } catch (error) {
            console.error('❌ Understaffing SMS check failed:', error);
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

        const dateStr = request.data?.date || get36hDateStr();
        const trigger = request.data?.trigger || 'manual';
        console.log(`📱 Manual understaffing check for ${dateStr} by ${request.auth.uid}`);
        return await checkAndSendIfUnderstaffed(dateStr, trigger);
    }
);

module.exports = {
    guideShiftReminderScheduled,
    guideShiftReminderManual,
};
