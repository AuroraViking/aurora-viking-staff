/**
 * Reports Module
 * Handles tour report generation and related Firestore triggers
 */
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall } = require('firebase-functions/v2/https');
const { onDocumentWritten, onDocumentCreated } = require('firebase-functions/v2/firestore');
const { google } = require('googleapis');
const { db } = require('../utils/firebase');
const { DRIVE_FOLDER_ID } = require('../config');
const { sendNotificationToAdminsOnly } = require('../utils/notifications');
const {
    getGoogleAuth,
    createSheetInFolder,
    populateSheetWithReportData,
    getAuroraRatingDisplay,
    getBestAuroraRating,
} = require('../utils/google_auth');

/**
 * DEFENSIVE generateReport - Works at any stage of the tour
 * Handles missing data gracefully
 */
async function generateReport(targetDate) {
    console.log(`📅 Generating report for: ${targetDate}`);

    // ========== STEP 1: Get cached bookings ==========
    let bookings = [];
    try {
        const cacheDoc = await db.collection('cached_bookings').doc(targetDate).get();

        if (!cacheDoc.exists) {
            console.log('⚠️ No cached_bookings document found for this date.');
        } else {
            const cachedData = cacheDoc.data();
            bookings = cachedData.bookings || [];
            console.log(`📋 Found ${bookings.length} bookings in cached_bookings`);
        }
    } catch (error) {
        console.log('⚠️ Could not fetch cached_bookings:', error.message);
    }

    // ========== STEP 1.5: Get pickup_assignments (SOURCE OF TRUTH!) ==========
    const pickupAssignments = {};
    try {
        const assignmentsSnapshot = await db.collection('pickup_assignments')
            .where('date', '==', targetDate)
            .get();

        assignmentsSnapshot.forEach((doc) => {
            const data = doc.data();
            if (data.bookingId && data.guideId) {
                pickupAssignments[data.bookingId] = {
                    guideId: data.guideId,
                    guideName: data.guideName || 'Unknown Guide',
                };
            }
        });
        console.log(`📋 Found ${Object.keys(pickupAssignments).length} assignments in pickup_assignments collection`);
    } catch (error) {
        console.log('⚠️ Could not fetch pickup_assignments:', error.message);
    }

    // ========== STEP 1.6: Merge assignments into bookings ==========
    bookings = bookings.map((booking) => {
        const bookingId = booking.id || booking.bookingId;
        const assignment = pickupAssignments[bookingId];

        if (assignment) {
            return {
                ...booking,
                assignedGuideId: assignment.guideId,
                assignedGuideName: assignment.guideName,
            };
        } else if (booking.assignedGuideId) {
            return booking;
        } else {
            return booking;
        }
    });

    const assignedCount = bookings.filter(b => b.assignedGuideId).length;
    console.log(`✅ After merging: ${assignedCount}/${bookings.length} bookings have guide assignments`);

    if (bookings.length === 0) {
        console.log('⚠️ Bookings array is empty.');
        return { success: false, message: 'No bookings in cache', date: targetDate };
    }

    // ========== STEP 2: Get bus-guide assignments (optional) ==========
    const guideToBus = {};
    try {
        const busAssignmentsSnapshot = await db
            .collection('bus_guide_assignments')
            .where('date', '==', targetDate)
            .get();

        busAssignmentsSnapshot.forEach((doc) => {
            const data = doc.data();
            if (data.guideId) {
                guideToBus[data.guideId] = {
                    busId: data.busId || null,
                    busName: data.busName || null,
                };
            }
        });
        console.log(`🚌 Found ${Object.keys(guideToBus).length} bus-guide assignments`);
    } catch (error) {
        console.log('⚠️ Could not fetch bus assignments (this is okay):', error.message);
    }

    // ========== STEP 3: Get end-of-shift reports (optional) ==========
    const guideReports = {};
    try {
        const endOfShiftSnapshot = await db
            .collection('end_of_shift_reports')
            .where('date', '==', targetDate)
            .get();

        endOfShiftSnapshot.forEach((doc) => {
            const data = doc.data();
            if (data.guideId) {
                guideReports[data.guideId] = {
                    auroraRating: data.auroraRating || null,
                    auroraRatingDisplay: data.auroraRating ? getAuroraRatingDisplay(data.auroraRating) : null,
                    shouldRequestReviews: data.shouldRequestReviews !== false,
                    notes: data.notes || null,
                    submittedAt: data.createdAt || null,
                };
            }
        });
        console.log(`📝 Found ${Object.keys(guideReports).length} end-of-shift reports`);
    } catch (error) {
        console.log('⚠️ Could not fetch end-of-shift reports (this is okay):', error.message);
    }

    // ========== STEP 4: Group bookings by assigned guide ==========
    const guideData = {};
    const unassignedBookings = [];

    bookings.forEach((booking) => {
        const guideId = booking.assignedGuideId;
        const guideName = booking.assignedGuideName || 'Unknown Guide';

        if (guideId) {
            if (!guideData[guideId]) {
                const busInfo = guideToBus[guideId] || {};
                const shiftReport = guideReports[guideId] || {};

                guideData[guideId] = {
                    guideName: guideName,
                    busId: busInfo.busId || null,
                    busName: busInfo.busName || null,
                    auroraRating: shiftReport.auroraRating || null,
                    auroraRatingDisplay: shiftReport.auroraRatingDisplay || null,
                    shouldRequestReviews: shiftReport.shouldRequestReviews ?? true,
                    shiftNotes: shiftReport.notes || null,
                    hasSubmittedReport: !!shiftReport.auroraRating,
                    totalPassengers: 0,
                    bookings: [],
                };
            }

            const passengers = booking.totalParticipants || booking.numberOfGuests || 0;
            guideData[guideId].bookings.push(booking);
            guideData[guideId].totalPassengers += passengers;
        } else {
            unassignedBookings.push(booking);
        }
    });

    console.log(`👥 Found ${Object.keys(guideData).length} guides with assignments`);
    console.log(`⚠️ ${unassignedBookings.length} unassigned bookings`);

    // ========== STEP 5: Calculate totals ==========
    let totalPassengers = 0;
    let guidesWithReports = 0;

    Object.values(guideData).forEach((guide) => {
        totalPassengers += guide.totalPassengers;
        if (guide.hasSubmittedReport) guidesWithReports++;
    });

    const auroraRatings = Object.values(guideData)
        .filter((g) => g.auroraRating)
        .map((g) => g.auroraRating);

    const auroraSummary = auroraRatings.length > 0 ? getBestAuroraRating(auroraRatings) : null;

    let unassignedPassengers = 0;
    unassignedBookings.forEach((b) => {
        unassignedPassengers += b.totalParticipants || b.numberOfGuests || 0;
    });

    const totalNoShows = bookings.filter(b => b.isNoShow === true).length;

    // ========== STEP 6: Build report data ==========
    const reportData = {
        date: targetDate,
        generatedAt: new Date().toISOString(),
        lastUpdatedAt: new Date().toISOString(),
        totalGuides: Object.keys(guideData).length,
        guidesWithReports: guidesWithReports,
        totalPassengers: totalPassengers,
        totalBookings: bookings.length,
        totalNoShows: totalNoShows,
        unassignedBookings: unassignedBookings.length,
        unassignedPassengers: unassignedPassengers,
        auroraSummary: auroraSummary,
        auroraReports: auroraRatings.length,
        guides: Object.entries(guideData).map(([guideId, data]) => ({
            guideId,
            guideName: data.guideName,
            busId: data.busId,
            busName: data.busName,
            auroraRating: data.auroraRating,
            auroraRatingDisplay: data.auroraRatingDisplay,
            shouldRequestReviews: data.shouldRequestReviews ?? true,
            shiftNotes: data.shiftNotes,
            hasSubmittedReport: data.hasSubmittedReport,
            totalPassengers: data.totalPassengers,
            bookingCount: data.bookings.length,
            bookings: data.bookings.map((b) => ({
                id: b.id || b.bookingId || 'unknown',
                customerName: b.customerFullName || b.customerName || 'Unknown',
                participants: b.totalParticipants || b.numberOfGuests || 0,
                pickupLocation: b.pickupPlaceName || b.pickupLocation || 'Unknown',
                pickupTime: b.pickupTime || null,
                phone: b.customerPhone || b.phoneNumber || '',
                email: b.customerEmail || b.email || '',
                confirmationCode: b.confirmationCode || '',
                isArrived: b.isArrived || false,
                isCompleted: b.isCompleted || false,
                isNoShow: b.isNoShow || false,
            })),
        })),
    };

    // Include unassigned if any
    if (unassignedBookings.length > 0) {
        reportData.unassigned = {
            guideName: '⚠️ UNASSIGNED',
            totalPassengers: unassignedPassengers,
            bookingCount: unassignedBookings.length,
            bookings: unassignedBookings.map((b) => ({
                id: b.id || b.bookingId || 'unknown',
                customerName: b.customerFullName || b.customerName || 'Unknown',
                participants: b.totalParticipants || b.numberOfGuests || 0,
                pickupLocation: b.pickupPlaceName || b.pickupLocation || 'Unknown',
                pickupTime: b.pickupTime || null,
                isNoShow: b.isNoShow || false,
            })),
        };
    }

    // ========== STEP 7: Save to Firestore ==========
    try {
        await db.collection('tour_reports').doc(targetDate).set(reportData, { merge: true });
        console.log(`✅ Report saved to Firestore: tour_reports/${targetDate}`);
    } catch (error) {
        console.error('❌ Error saving to Firestore:', error);
        return { success: false, message: 'Error saving report: ' + error.message, date: targetDate };
    }

    // ========== STEP 8: Create/Update Google Sheet ==========
    let sheetUrl = null;
    try {
        const existingReport = await db.collection('tour_reports').doc(targetDate).get();
        const existingData = existingReport.data() || {};
        const existingSheetId = existingData.spreadsheetId;

        const auth = await getGoogleAuth();
        let spreadsheetId;

        if (existingSheetId) {
            console.log(`📊 Updating existing sheet: ${existingSheetId}`);
            spreadsheetId = existingSheetId;

            const sheets = google.sheets({ version: 'v4', auth });
            try {
                await sheets.spreadsheets.values.clear({
                    spreadsheetId,
                    range: 'Sheet1!A:Z',
                });
            } catch (clearError) {
                console.log('⚠️ Could not clear sheet (might be new):', clearError.message);
            }

            await populateSheetWithReportData(auth, spreadsheetId, reportData);
        } else {
            const sheetTitle = `Aurora Viking Tour Report - ${targetDate}`;
            spreadsheetId = await createSheetInFolder(auth, sheetTitle, DRIVE_FOLDER_ID);
            await populateSheetWithReportData(auth, spreadsheetId, reportData);
        }

        sheetUrl = `https://docs.google.com/spreadsheets/d/${spreadsheetId}`;

        await db.collection('tour_reports').doc(targetDate).update({
            sheetUrl: sheetUrl,
            spreadsheetId: spreadsheetId,
        });

        console.log(`📊 Google Sheet ready: ${sheetUrl}`);
    } catch (sheetError) {
        console.error('⚠️ Google Sheet error (report still saved):', sheetError.message);
    }

    return {
        success: true,
        date: targetDate,
        guides: Object.keys(guideData).length,
        guidesWithReports: guidesWithReports,
        totalPassengers: totalPassengers,
        totalBookings: bookings.length,
        auroraSummary: auroraSummary,
        sheetUrl: sheetUrl,
    };
}

// Helper: Check if any guide assignments changed
function hasAssignmentChanged(beforeBookings, afterBookings) {
    if (beforeBookings.length !== afterBookings.length) {
        return true;
    }

    const beforeAssignments = {};
    const afterAssignments = {};

    beforeBookings.forEach((b) => {
        beforeAssignments[b.id || b.bookingId] = b.assignedGuideId || null;
    });

    afterBookings.forEach((b) => {
        afterAssignments[b.id || b.bookingId] = b.assignedGuideId || null;
    });

    for (const bookingId of Object.keys(afterAssignments)) {
        if (beforeAssignments[bookingId] !== afterAssignments[bookingId]) {
            console.log(`📝 Assignment changed for booking ${bookingId}: ${beforeAssignments[bookingId]} → ${afterAssignments[bookingId]}`);
            return true;
        }
    }

    for (const bookingId of Object.keys(afterAssignments)) {
        if (!(bookingId in beforeAssignments)) {
            console.log(`📝 New booking added: ${bookingId}`);
            return true;
        }
    }

    return false;
}

// ============================================
// FIRESTORE TRIGGERS
// ============================================

/**
 * Trigger: Generate report when end-of-shift is submitted
 */
const onEndOfShiftSubmitted = onDocumentCreated(
    {
        document: 'end_of_shift_reports/{reportId}',
        region: 'us-central1',
    },
    async (event) => {
        const snapshot = event.data;
        if (!snapshot) {
            console.log('No data in snapshot');
            return null;
        }

        const data = snapshot.data();
        const date = data.date;
        const guideName = data.guideName;

        console.log(`🌙 End of shift submitted by ${guideName} for ${date}`);

        try {
            const result = await generateReport(date);
            console.log(`✅ Report generated/updated for ${date}:`, result);
            return result;
        } catch (error) {
            console.error(`❌ Failed to generate report for ${date}:`, error);
            return null;
        }
    }
);

/**
 * Trigger: Update report when pickups change
 */
const onPickupAssignmentsChanged = onDocumentWritten(
    {
        document: 'cached_bookings/{date}',
        region: 'us-central1',
    },
    async (event) => {
        const date = event.params.date;

        if (!event.data.after.exists) {
            console.log(`📋 cached_bookings/${date} was deleted, skipping report update`);
            return null;
        }

        const beforeData = event.data.before.exists ? event.data.before.data() : null;
        const afterData = event.data.after.data();

        const beforeBookings = beforeData?.bookings || [];
        const afterBookings = afterData?.bookings || [];

        // SAFETY: Detect dangerous "fresh fetch" that lost all assignments
        const beforeAssignedCount = beforeBookings.filter(b => b.assignedGuideId).length;
        const afterAssignedCount = afterBookings.filter(b => b.assignedGuideId).length;

        if (beforeAssignedCount > 0 && afterAssignedCount === 0 && afterBookings.length > 0) {
            console.log(`⚠️ DANGER: cached_bookings refresh lost all ${beforeAssignedCount} assignments!`);
            return null;
        }

        const assignmentChanged = hasAssignmentChanged(beforeBookings, afterBookings);

        if (!assignmentChanged) {
            console.log(`📋 No assignment changes detected for ${date}, skipping report update`);
            return null;
        }

        console.log(`📋 Pickup assignments changed for ${date}, updating tour report...`);

        // Rate limiting
        const reportDoc = await db.collection('tour_reports').doc(date).get();
        if (reportDoc.exists) {
            const lastUpdated = reportDoc.data()?.lastUpdatedAt;
            if (lastUpdated) {
                const lastUpdateTime = new Date(lastUpdated);
                const now = new Date();
                const secondsSinceUpdate = (now - lastUpdateTime) / 1000;

                if (secondsSinceUpdate < 60) {
                    console.log(`⏱️ Report was updated ${secondsSinceUpdate.toFixed(0)}s ago, skipping (rate limit)`);
                    return null;
                }
            }
        }

        try {
            const result = await generateReport(date);
            console.log(`✅ Tour report auto-updated for ${date}:`, result);
            return result;
        } catch (error) {
            console.error(`❌ Failed to auto-update report for ${date}:`, error);
            return null;
        }
    }
);

/**
 * Trigger: Update report when bus assignment changes
 */
const onBusAssignmentChanged = onDocumentWritten(
    {
        document: 'bus_guide_assignments/{assignmentId}',
        region: 'us-central1',
    },
    async (event) => {
        const afterData = event.data.after.exists ? event.data.after.data() : null;
        const beforeData = event.data.before.exists ? event.data.before.data() : null;

        const date = afterData?.date || beforeData?.date;

        if (!date) {
            console.log('⚠️ No date found in bus_guide_assignment, skipping');
            return null;
        }

        console.log(`🚌 Bus assignment changed for ${date}, updating tour report...`);

        // Rate limiting
        const reportDoc = await db.collection('tour_reports').doc(date).get();
        if (reportDoc.exists) {
            const lastUpdated = reportDoc.data()?.lastUpdatedAt;
            if (lastUpdated) {
                const lastUpdateTime = new Date(lastUpdated);
                const now = new Date();
                const secondsSinceUpdate = (now - lastUpdateTime) / 1000;

                if (secondsSinceUpdate < 30) {
                    console.log(`⏱️ Report was updated ${secondsSinceUpdate.toFixed(0)}s ago, skipping`);
                    return null;
                }
            }
        }

        try {
            const result = await generateReport(date);
            console.log(`✅ Tour report auto-updated for ${date} (bus assignment):`, result);
            return result;
        } catch (error) {
            console.error(`❌ Failed to auto-update report:`, error);
            return null;
        }
    }
);

/**
 * Scheduled: 5am fallback report generation (Iceland time)
 */
const generateTourReport = onSchedule(
    {
        schedule: '0 5 * * *',
        timeZone: 'Atlantic/Reykjavik',
        region: 'us-central1',
    },
    async () => {
        console.log('🌅 Starting 5am fallback report generation...');

        const now = new Date();
        const yesterday = new Date(now);
        yesterday.setDate(yesterday.getDate() - 1);

        const icelandYesterday = new Date(yesterday.toLocaleString('en-US', { timeZone: 'Atlantic/Reykjavik' }));
        const dateStr = `${icelandYesterday.getFullYear()}-${String(icelandYesterday.getMonth() + 1).padStart(2, '0')}-${String(icelandYesterday.getDate()).padStart(2, '0')}`;

        console.log(`📅 Generating fallback report for: ${dateStr}`);

        try {
            const result = await generateReport(dateStr);
            console.log(`✅ Fallback report result:`, result);
            return result;
        } catch (error) {
            console.error(`❌ Fallback report failed:`, error);
            return null;
        }
    }
);

/**
 * Manual trigger for report generation
 */
const generateTourReportManual = onCall(
    {
        region: 'us-central1',
    },
    async (request) => {
        console.log('📝 Manual report generation requested');

        const dateParam = request.data?.date;

        let targetDate;
        if (dateParam) {
            targetDate = dateParam;
        } else {
            const now = new Date();
            const yesterday = new Date(now);
            yesterday.setDate(yesterday.getDate() - 1);
            const icelandYesterday = new Date(yesterday.toLocaleString('en-US', { timeZone: 'Atlantic/Reykjavik' }));
            targetDate = `${icelandYesterday.getFullYear()}-${String(icelandYesterday.getMonth() + 1).padStart(2, '0')}-${String(icelandYesterday.getDate()).padStart(2, '0')}`;
        }

        console.log(`📅 Generating report for: ${targetDate}`);
        return await generateReport(targetDate);
    }
);

// ============================================
// PICKUP STATUS NOTIFICATIONS
// ============================================

/**
 * Trigger: Notify admins when ALL bookings for a guide are picked up (arrived).
 * Watches booking_status/{date}_{bookingId} for isArrived changes.
 */
const onPickupCompleted = onDocumentWritten(
    {
        document: 'booking_status/{documentId}',
        region: 'us-central1',
    },
    async (event) => {
        const documentId = event.params.documentId;
        console.log(`🔔 onPickupCompleted triggered for: ${documentId}`);

        const beforeData = event.data.before.exists ? event.data.before.data() : {};
        const afterData = event.data.after.exists ? event.data.after.data() : null;

        if (!afterData) {
            console.log('ℹ️ Document deleted, skipping');
            return null;
        }

        const wasArrived = beforeData.isArrived === true;
        const isNowArrived = afterData.isArrived === true;

        // Only fire when this booking just flipped to arrived
        if (wasArrived || !isNowArrived) {
            console.log(`ℹ️ isArrived did not change from false→true (was: ${wasArrived}, now: ${isNowArrived}), skipping`);
            return null;
        }

        // Parse date from document ID (format: YYYY-MM-DD_bookingId)
        const parts = documentId.split('_');
        if (parts.length < 2) {
            console.log('⚠️ Document ID format unexpected:', documentId);
            return null;
        }
        const date = parts[0]; // YYYY-MM-DD
        const bookingId = parts.slice(1).join('_'); // rest is booking ID
        const guideId = afterData.guideId || null;
        const guideName = afterData.guideName || 'Unknown guide';
        const customerName = afterData.customerName || bookingId;

        console.log(`✅ Booking ${bookingId} (${customerName}) marked arrived for date ${date}, guide: ${guideName}`);

        // Check if ALL bookings for this guide on this date are now arrived
        if (guideId) {
            try {
                // Get all booking_status docs for this date that belong to this guide
                const allStatusDocs = await db
                    .collection('booking_status')
                    .where('guideId', '==', guideId)
                    .where('date', '==', date)
                    .get();

                if (!allStatusDocs.empty) {
                    const totalForGuide = allStatusDocs.size;
                    const arrivedForGuide = allStatusDocs.docs.filter(d => d.data().isArrived === true).length;

                    console.log(`📊 Guide ${guideName}: ${arrivedForGuide}/${totalForGuide} bookings arrived`);

                    if (arrivedForGuide === totalForGuide && totalForGuide > 0) {
                        console.log(`🎉 All ${totalForGuide} pickups complete for ${guideName} on ${date}!`);
                        await sendNotificationToAdminsOnly(
                            '✅ All Pickups Complete',
                            `${guideName} has picked up all ${totalForGuide} passenger group${totalForGuide > 1 ? 's' : ''} (${date})`,
                            { type: 'pickup_complete', guideId, guideName, date }
                        );
                        return null;
                    }
                }
            } catch (err) {
                console.log('⚠️ Could not check guide completion (guideId field may not be stored):', err.message);
            }
        }

        // Fallback: check if ALL bookings for the date (regardless of guide) are arrived
        try {
            const allDateDocs = await db
                .collection('booking_status')
                .where('date', '==', date)
                .get();

            if (!allDateDocs.empty) {
                const total = allDateDocs.size;
                const arrived = allDateDocs.docs.filter(d => d.data().isArrived === true).length;
                const noShows = allDateDocs.docs.filter(d => d.data().isNoShow === true).length;
                const accounted = arrived + noShows;

                console.log(`📊 Date ${date}: ${arrived} arrived, ${noShows} no-shows, ${total} total`);

                if (accounted >= total && total > 0) {
                    console.log(`🎉 All ${total} bookings accounted for on ${date}!`);
                    await sendNotificationToAdminsOnly(
                        '✅ All Pickups Done',
                        `All ${total} bookings for ${date} are accounted for (${arrived} arrived, ${noShows} no-show)`,
                        { type: 'all_pickups_complete', date, arrived, noShows }
                    );
                }
            }
        } catch (err) {
            console.error('❌ Error checking all pickups:', err);
        }

        return null;
    }
);

/**
 * Trigger: Notify admins immediately when a no-show is marked.
 */
const onNoShowMarked = onDocumentWritten(
    {
        document: 'booking_status/{documentId}',
        region: 'us-central1',
    },
    async (event) => {
        const documentId = event.params.documentId;

        const beforeData = event.data.before.exists ? event.data.before.data() : {};
        const afterData = event.data.after.exists ? event.data.after.data() : null;

        if (!afterData) return null;

        const wasNoShow = beforeData.isNoShow === true;
        const isNowNoShow = afterData.isNoShow === true;

        // Only fire when this booking just flipped to no-show
        if (wasNoShow || !isNowNoShow) return null;

        // Parse date from document ID
        const parts = documentId.split('_');
        const date = parts[0];
        const customerName = afterData.customerName || documentId;
        const guideName = afterData.guideName || 'Unknown guide';
        const pickupPlace = afterData.pickupPlaceName || afterData.pickupPlace || 'Unknown location';

        console.log(`🚫 No-show marked: ${customerName} at ${pickupPlace} (guide: ${guideName}, ${date})`);

        await sendNotificationToAdminsOnly(
            '🚫 No-Show Reported',
            `${customerName} — ${pickupPlace} (guide: ${guideName})`,
            { type: 'no_show', date, customerName, guideName, pickupPlace }
        );

        return null;
    }
);


module.exports = {
    generateReport,
    onEndOfShiftSubmitted,
    onPickupAssignmentsChanged,
    onBusAssignmentChanged,
    generateTourReport,
    generateTourReportManual,
    onPickupCompleted,
    onNoShowMarked,
};
