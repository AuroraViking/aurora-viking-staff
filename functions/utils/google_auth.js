/**
 * Google Auth and Sheets utilities
 * Handles authentication and Google Sheets operations
 */
const { google } = require('googleapis');
const { DRIVE_FOLDER_ID } = require('../config');

/**
 * Get Google Auth client using Application Default Credentials
 */
async function getGoogleAuth() {
    const auth = new google.auth.GoogleAuth({
        scopes: [
            'https://www.googleapis.com/auth/spreadsheets',
            'https://www.googleapis.com/auth/drive.file',
            'https://www.googleapis.com/auth/drive',
        ],
    });
    return auth;
}

/**
 * Create a new Google Sheet in a specific Drive folder
 */
async function createSheetInFolder(auth, title, folderId = DRIVE_FOLDER_ID) {
    const drive = google.drive({ version: 'v3', auth });
    const sheets = google.sheets({ version: 'v4', auth });

    // Create a new spreadsheet
    const spreadsheet = await sheets.spreadsheets.create({
        requestBody: {
            properties: {
                title: title,
            },
        },
    });

    const spreadsheetId = spreadsheet.data.spreadsheetId;
    const fileId = spreadsheetId;

    console.log(`📄 Created spreadsheet: ${title} (${spreadsheetId})`);

    // Move the spreadsheet to the target folder
    const file = await drive.files.get({
        fileId: fileId,
        fields: 'parents',
    });

    const previousParents = file.data.parents ? file.data.parents.join(',') : '';

    // Move to new folder
    await drive.files.update({
        fileId: fileId,
        addParents: folderId,
        removeParents: previousParents,
        fields: 'id, parents',
    });

    console.log(`📁 Moved spreadsheet to folder: ${folderId}`);

    return spreadsheetId;
}

/**
 * Populate a Google Sheet with report data
 */
async function populateSheetWithReportData(auth, spreadsheetId, reportData) {
    const sheets = google.sheets({ version: 'v4', auth });

    const rows = [];

    // Header
    rows.push([`Aurora Viking Tour Report - ${reportData.date}`]);
    rows.push([`Generated: ${new Date().toLocaleString('en-GB', { timeZone: 'Atlantic/Reykjavik' })}`]);
    rows.push([
        `Guides: ${reportData.totalGuides}`,
        `Passengers: ${reportData.totalPassengers}`,
        `Bookings: ${reportData.totalBookings}`,
        `Reports: ${reportData.guidesWithReports}/${reportData.totalGuides}`,
    ]);

    // Aurora summary (if available)
    if (reportData.auroraSummary) {
        rows.push([`🌌 Aurora Tonight: ${reportData.auroraSummary.display}`]);
    } else {
        rows.push([`🌌 Aurora: No reports submitted yet`]);
    }

    rows.push([]);

    // Each guide
    reportData.guides.forEach((guide) => {
        const busInfo = guide.busName ? `🚌 ${guide.busName}` : '🚌 -';
        const auroraInfo = guide.auroraRatingDisplay || '⏳ Pending';
        const reviewInfo = guide.shouldRequestReviews === false ? '❌ No Reviews' : '';

        rows.push([
            `👤 ${guide.guideName}`,
            busInfo,
            `🌌 ${auroraInfo}`,
            reviewInfo,
            `${guide.totalPassengers} pax`,
        ]);

        if (guide.shiftNotes) {
            rows.push([`   📝 ${guide.shiftNotes}`]);
        }

        // Column headers
        rows.push(['Customer', 'Pax', 'Pickup', 'Time', 'Phone', 'Status']);

        // Bookings
        guide.bookings.forEach((booking) => {
            const status = booking.isNoShow ? '❌ NO SHOW' : booking.isCompleted ? '✅' : booking.isArrived ? '📍' : '⏳';
            const time = booking.pickupTime ? (booking.pickupTime.split('T')[1] || '').substring(0, 5) : '';
            rows.push([
                booking.customerName,
                booking.participants,
                (booking.pickupLocation || '').substring(0, 40),
                time,
                booking.phone,
                status,
            ]);
        });

        rows.push([]);
    });

    // Write to sheet
    await sheets.spreadsheets.values.update({
        spreadsheetId,
        range: 'Sheet1!A1',
        valueInputOption: 'USER_ENTERED',
        requestBody: { values: rows },
    });

    console.log('✨ Sheet populated');
}

/**
 * Get display text for aurora rating
 */
function getAuroraRatingDisplay(rating) {
    const ratings = {
        'not_seen': 'Not seen 😔',
        'camera_only': 'Only through camera 📷',
        'a_little': 'A little bit ✨',
        'good': 'Good 🌟',
        'great': 'Great ⭐',
        'exceptional': 'Exceptional 🤩',
    };
    return ratings[rating] || rating;
}

/**
 * Get the best aurora rating from multiple guides
 */
function getBestAuroraRating(ratings) {
    const order = ['exceptional', 'great', 'good', 'a_little', 'camera_only', 'not_seen'];
    for (const level of order) {
        if (ratings.includes(level)) {
            return {
                rating: level,
                display: getAuroraRatingDisplay(level),
            };
        }
    }
    return null;
}

module.exports = {
    getGoogleAuth,
    createSheetInFolder,
    populateSheetWithReportData,
    getAuroraRatingDisplay,
    getBestAuroraRating,
};
