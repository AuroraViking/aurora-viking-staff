/**
 * Google Auth and Sheets utilities
 * Handles authentication, Google Sheets, and Google Drive operations
 */
const { google } = require('googleapis');
const { DRIVE_FOLDER_ID } = require('../config');

// Service account and Drive owner for impersonation
const SA_EMAIL = '975783791718-compute@developer.gserviceaccount.com';
const DRIVE_OWNER_EMAIL = 'photo@auroraviking.com';

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
 * Get an access token impersonating photo@auroraviking.com
 * Files created with this auth are owned by photo@ and use its 2TB storage.
 * Uses IAM signJwt API (no key file needed, uses domain-wide delegation).
 */
async function getDriveAuthAsPhotoUser() {
    const { IAMCredentialsClient } = require('@google-cloud/iam-credentials');
    const iamClient = new IAMCredentialsClient();

    const now = Math.floor(Date.now() / 1000);
    const jwtPayload = {
        iss: SA_EMAIL,
        sub: DRIVE_OWNER_EMAIL,
        scope: 'https://www.googleapis.com/auth/drive https://www.googleapis.com/auth/drive.file',
        aud: 'https://oauth2.googleapis.com/token',
        iat: now,
        exp: now + 3600,
    };

    const [signResponse] = await iamClient.signJwt({
        name: `projects/-/serviceAccounts/${SA_EMAIL}`,
        payload: JSON.stringify(jwtPayload),
    });

    const signedJwt = signResponse.signedJwt;

    const fetch = require('node-fetch');
    const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${signedJwt}`,
    });

    const tokenData = await tokenResponse.json();
    if (tokenData.error) {
        throw new Error(`Token exchange failed: ${tokenData.error_description || tokenData.error}`);
    }

    const oauth2Client = new google.auth.OAuth2();
    oauth2Client.setCredentials({ access_token: tokenData.access_token });
    return oauth2Client;
}

/**
 * Find or create a subfolder inside a parent folder.
 * Returns the folder ID.
 */
async function findOrCreateSubfolder(auth, parentFolderId, folderName) {
    const drive = google.drive({ version: 'v3', auth });

    // Search for existing subfolder
    const searchResult = await drive.files.list({
        q: `'${parentFolderId}' in parents and name = '${folderName}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false`,
        fields: 'files(id, name)',
        spaces: 'drive',
    });

    if (searchResult.data.files && searchResult.data.files.length > 0) {
        const folderId = searchResult.data.files[0].id;
        console.log(`📁 Found existing folder '${folderName}': ${folderId}`);
        return folderId;
    }

    // Create new subfolder
    const folderMetadata = {
        name: folderName,
        mimeType: 'application/vnd.google-apps.folder',
        parents: [parentFolderId],
    };

    const folder = await drive.files.create({
        requestBody: folderMetadata,
        fields: 'id',
    });

    console.log(`📁 Created new folder '${folderName}': ${folder.data.id}`);
    return folder.data.id;
}

/**
 * Create a new Google Sheet directly inside a specific Drive folder.
 * Uses Drive API files.create with parents to avoid the create-then-move
 * pattern that causes permission errors.
 */
async function createSheetInFolder(auth, title, folderId = DRIVE_FOLDER_ID) {
    const drive = google.drive({ version: 'v3', auth });

    // Create a spreadsheet directly in the target folder
    const file = await drive.files.create({
        requestBody: {
            name: title,
            mimeType: 'application/vnd.google-apps.spreadsheet',
            parents: [folderId],
        },
        fields: 'id',
    });

    const spreadsheetId = file.data.id;
    console.log(`📄 Created spreadsheet in folder ${folderId}: ${title} (${spreadsheetId})`);

    return spreadsheetId;
}

/**
 * Populate a Google Sheet with report data (legacy single-tab format)
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
 * Populate a Google Sheet with ENHANCED report data — multi-tab, formatted
 * Creates a Summary tab + one tab per guide with full manifest, GPS, and notes
 */
async function populateSheetWithEnhancedReportData(auth, spreadsheetId, reportData) {
    const sheets = google.sheets({ version: 'v4', auth });

    // ── Step 1: Rename default Sheet1 to "Summary" and add guide tabs ──
    const guideTabNames = (reportData.guides || []).map((g) => {
        // Sanitize sheet names (max 100 chars, no special chars)
        const name = (g.guideName || 'Unknown').replace(/[\\/*?[\]:]/g, '').substring(0, 90);
        return name;
    });

    // Get existing sheet info
    const spreadsheetInfo = await sheets.spreadsheets.get({ spreadsheetId });
    const defaultSheetId = spreadsheetInfo.data.sheets[0].properties.sheetId;

    // Build batch update requests: rename Sheet1 → Summary, add guide tabs
    const batchRequests = [
        {
            updateSheetProperties: {
                properties: {
                    sheetId: defaultSheetId,
                    title: 'Summary',
                },
                fields: 'title',
            },
        },
    ];

    guideTabNames.forEach((name, index) => {
        batchRequests.push({
            addSheet: {
                properties: {
                    title: name,
                    index: index + 1,
                },
            },
        });
    });

    await sheets.spreadsheets.batchUpdate({
        spreadsheetId,
        requestBody: { requests: batchRequests },
    });

    // ── Step 2: Populate Summary tab ──
    const summaryRows = [];
    summaryRows.push(['Aurora Viking Tour Report']);
    summaryRows.push([`Date: ${reportData.date}`]);
    summaryRows.push([`Generated: ${new Date().toLocaleString('en-GB', { timeZone: 'Atlantic/Reykjavik' })}`]);
    summaryRows.push([]);

    // Aurora summary
    if (reportData.auroraSummary) {
        summaryRows.push(['🌌 Aurora Tonight', reportData.auroraSummary.display || '']);
    } else {
        summaryRows.push(['🌌 Aurora Tonight', 'No reports submitted']);
    }
    summaryRows.push([]);

    // Overview stats
    summaryRows.push(['OVERVIEW']);
    summaryRows.push(['Total Guides', reportData.totalGuides || 0]);
    summaryRows.push(['Total Passengers', reportData.totalPassengers || 0]);
    summaryRows.push(['Total Bookings', reportData.totalBookings || 0]);
    summaryRows.push(['No-Shows', reportData.totalNoShows || 0]);
    summaryRows.push(['Guides Reported', `${reportData.guidesWithReports || 0} / ${reportData.totalGuides || 0}`]);
    summaryRows.push([]);

    // Guide overview table
    summaryRows.push(['GUIDE SUMMARY']);
    summaryRows.push(['Guide', 'Bus', 'Passengers', 'Bookings', 'Aurora', 'GPS Distance', 'GPS Duration', 'Notes']);

    (reportData.guides || []).forEach((guide) => {
        const gps = guide.gpsTrail || {};
        summaryRows.push([
            guide.guideName || 'Unknown',
            guide.busName || '-',
            guide.totalPassengers || 0,
            guide.bookingCount || (guide.bookings || []).length,
            guide.auroraRatingDisplay || 'Pending',
            gps.totalDistanceKm ? `${gps.totalDistanceKm.toFixed(1)} km` : 'No data',
            gps.durationStr || 'No data',
            guide.shiftNotes || '-',
        ]);
    });

    // Unassigned bookings summary
    if (reportData.unassigned && reportData.unassigned.bookingCount > 0) {
        summaryRows.push([
            '⚠️ UNASSIGNED',
            '-',
            reportData.unassigned.totalPassengers || 0,
            reportData.unassigned.bookingCount || 0,
            '-',
            '-',
            '-',
            '-',
        ]);
    }

    await sheets.spreadsheets.values.update({
        spreadsheetId,
        range: 'Summary!A1',
        valueInputOption: 'USER_ENTERED',
        requestBody: { values: summaryRows },
    });

    // ── Step 3: Populate each guide tab ──
    for (let i = 0; i < guideTabNames.length; i++) {
        const guide = reportData.guides[i];
        const tabName = guideTabNames[i];
        const gps = guide.gpsTrail || {};
        const guideRows = [];

        // Guide header
        guideRows.push([`👤 ${guide.guideName || 'Unknown'}`]);
        guideRows.push([`Date: ${reportData.date}`]);
        guideRows.push([]);

        // Guide info
        guideRows.push(['GUIDE DETAILS']);
        guideRows.push(['Bus', guide.busName || 'Not assigned']);
        guideRows.push(['Total Passengers', guide.totalPassengers || 0]);
        guideRows.push(['Total Bookings', guide.bookingCount || (guide.bookings || []).length]);
        guideRows.push(['Aurora Rating', guide.auroraRatingDisplay || 'Not submitted']);
        guideRows.push(['Reviews Requested', guide.shouldRequestReviews !== false ? 'Yes' : 'No']);
        guideRows.push([]);

        // Guide notes
        if (guide.shiftNotes) {
            guideRows.push(['📝 GUIDE NOTES']);
            guideRows.push([guide.shiftNotes]);
            guideRows.push([]);
        }

        // GPS Trail summary
        guideRows.push(['🗺️ GPS TRAIL']);
        if (gps.totalDistanceKm) {
            guideRows.push(['Distance', `${gps.totalDistanceKm.toFixed(1)} km`]);
            guideRows.push(['Duration', gps.durationStr || 'Unknown']);
            guideRows.push(['Start Time', gps.startTimeStr || 'Unknown']);
            guideRows.push(['End Time', gps.endTimeStr || 'Unknown']);
            guideRows.push(['Max Speed', gps.maxSpeedKmh ? `${gps.maxSpeedKmh.toFixed(0)} km/h` : 'Unknown']);
            guideRows.push(['GPS Points', gps.pointCount || 0]);
        } else {
            guideRows.push(['No GPS data available for this tour']);
        }
        guideRows.push([]);

        // Customer manifest
        guideRows.push(['📋 CUSTOMER MANIFEST']);
        guideRows.push([
            '#', 'Customer Name', 'Pax', 'Pickup Location', 'Pickup Time',
            'Phone', 'Email', 'Confirmation Code', 'Status',
        ]);

        (guide.bookings || []).forEach((booking, idx) => {
            const status = booking.isNoShow
                ? '❌ NO SHOW'
                : booking.isCompleted
                    ? '✅ Complete'
                    : booking.isArrived
                        ? '📍 Arrived'
                        : '⏳ Pending';

            const pickupTime = booking.pickupTime
                ? (booking.pickupTime.split('T')[1] || '').substring(0, 5)
                : '';

            guideRows.push([
                idx + 1,
                booking.customerName || 'Unknown',
                booking.participants || 0,
                booking.pickupLocation || 'Unknown',
                pickupTime,
                booking.phone || '',
                booking.email || '',
                booking.confirmationCode || '',
                status,
            ]);
        });

        await sheets.spreadsheets.values.update({
            spreadsheetId,
            range: `'${tabName}'!A1`,
            valueInputOption: 'USER_ENTERED',
            requestBody: { values: guideRows },
        });
    }

    console.log('✨ Enhanced multi-tab sheet populated');
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
    getDriveAuthAsPhotoUser,
    findOrCreateSubfolder,
    createSheetInFolder,
    populateSheetWithReportData,
    populateSheetWithEnhancedReportData,
    getAuroraRatingDisplay,
    getBestAuroraRating,
};
