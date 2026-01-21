/**
 * Tour Status Module
 * Handles tour ON/OFF status for daily operations
 */
const { onRequest, onCall } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { admin, db } = require('../utils/firebase');
const { sendNotificationToAdminsOnly } = require('../utils/notifications');

// ============================================
// HELPER FUNCTIONS
// ============================================

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
 * Set tour status (admin only)
 */
const setTourStatus = onCall(
    {
        region: 'us-central1',
    },
    async (request) => {
        console.log('🔄 Setting tour status...');

        if (!request.auth) {
            throw new Error('You must be logged in to set tour status');
        }

        const uid = request.auth.uid;
        const { date, status, message } = request.data;

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

        return {
            success: true,
            date: dateString,
            displayDate: formatDateForDisplay(dateString),
            status: status,
            message: message || '',
            updatedByName: userName,
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

module.exports = {
    getTourStatus,
    setTourStatus,
    getTourStatusHistory,
    tourStatusReminder,
};
