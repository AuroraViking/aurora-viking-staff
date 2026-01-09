const {onRequest} = require('firebase-functions/v2/https');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {onCall} = require('firebase-functions/v2/https');
const {onDocumentWritten, onDocumentCreated} = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');
const {getFirestore} = require('firebase-admin/firestore');
const crypto = require('crypto');
const https = require('https');
const {google} = require('googleapis');

admin.initializeApp();

const db = getFirestore();

// ============================================
// CONFIGURATION - UPDATE THIS VALUE
// ============================================
const DRIVE_FOLDER_ID = '1NLkypBEnuxLpcDpTPdibAnGraF6fvtXC';  // The folder where reports will be saved
// To get this: Open the folder in Drive, copy the ID from the URL
// Example URL: https://drive.google.com/drive/folders/1ABC123xyz
// The ID is: 1ABC123xyz

// ============================================
// GOOGLE AUTH SETUP
// ============================================
async function getGoogleAuth() {
  // This uses Application Default Credentials (ADC)
  // In Cloud Functions, this automatically uses the service account
  const auth = new google.auth.GoogleAuth({
    scopes: [
      'https://www.googleapis.com/auth/spreadsheets',
      'https://www.googleapis.com/auth/drive.file',
    ],
  });
  return auth;
}

// ============================================
// CREATE GOOGLE SHEET IN DRIVE FOLDER
// ============================================
async function createSheetInFolder(auth, title, folderId) {
  const drive = google.drive({version: 'v3', auth});
  const sheets = google.sheets({version: 'v4', auth});
  
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
  // First, get the current parent(s)
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

// ========== HELPER: Populate sheet with report data ==========
async function populateSheetWithReportData(auth, spreadsheetId, reportData) {
  const sheets = google.sheets({version: 'v4', auth});

  const rows = [];

  // Header
  rows.push([`Aurora Viking Tour Report - ${reportData.date}`]);
  rows.push([`Generated: ${new Date().toLocaleString('en-GB', {timeZone: 'Atlantic/Reykjavik'})}`]);
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
      const status = booking.isCompleted ? '✅' : booking.isArrived ? '📍' : '⏳';
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
    requestBody: {values: rows},
  });

  console.log('✨ Sheet populated');
}

// Helper function to get display text for aurora rating
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

// Helper function to get the best aurora rating from multiple guides
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

// ============================================
// DEFENSIVE generateReport - Works at any stage of the tour
// ============================================
// This version handles:
// - No end_of_shift_reports yet (before tour ends)
// - No bus_guide_assignments (if buses not assigned)
// - Empty collections
// - Missing fields
async function generateReport(targetDate) {
  console.log(`📅 Generating report for: ${targetDate}`);

  // ========== STEP 1: Get cached bookings ==========
  let bookings = [];
  try {
    const cacheDoc = await db.collection('cached_bookings').doc(targetDate).get();
    
    if (!cacheDoc.exists) {
      console.log('⚠️ No cached_bookings document found for this date.');
      return {success: false, message: 'No cached bookings found', date: targetDate};
    }
    
    const cachedData = cacheDoc.data();
    bookings = cachedData.bookings || [];
    console.log(`📋 Found ${bookings.length} bookings in cached_bookings`);
  } catch (error) {
    console.error('❌ Error fetching cached_bookings:', error);
    return {success: false, message: 'Error fetching bookings: ' + error.message, date: targetDate};
  }

  if (bookings.length === 0) {
    console.log('⚠️ Bookings array is empty.');
    return {success: false, message: 'No bookings in cache', date: targetDate};
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
    // Not critical - continue without bus data
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
          shouldRequestReviews: data.shouldRequestReviews !== false, // Default to true
          notes: data.notes || null,
          submittedAt: data.createdAt || null,
        };
      }
    });
    console.log(`📝 Found ${Object.keys(guideReports).length} end-of-shift reports`);
  } catch (error) {
    // Not critical - continue without end-of-shift data
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
        // Get bus info (may not exist)
        const busInfo = guideToBus[guideId] || {};
        // Get end-of-shift report (may not exist)
        const shiftReport = guideReports[guideId] || {};

        guideData[guideId] = {
          guideName: guideName,
          busId: busInfo.busId || null,
          busName: busInfo.busName || null,
          // End of shift data (null if not submitted yet)
          auroraRating: shiftReport.auroraRating || null,
          auroraRatingDisplay: shiftReport.auroraRatingDisplay || null,
          shouldRequestReviews: shiftReport.shouldRequestReviews ?? true,
          shiftNotes: shiftReport.notes || null,
          hasSubmittedReport: !!shiftReport.auroraRating,
          // Booking data
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
    console.log(`  - ${guide.guideName}: ${guide.bookings.length} bookings, ${guide.totalPassengers} pax, Report: ${guide.hasSubmittedReport ? '✅' : '⏳'}`);
  });

  // Aurora summary (only if we have reports)
  const auroraRatings = Object.values(guideData)
    .filter((g) => g.auroraRating)
    .map((g) => g.auroraRating);

  const auroraSummary = auroraRatings.length > 0 ? getBestAuroraRating(auroraRatings) : null;

  // Unassigned passengers
  let unassignedPassengers = 0;
  unassignedBookings.forEach((b) => {
    unassignedPassengers += b.totalParticipants || b.numberOfGuests || 0;
  });

  // ========== STEP 6: Build report data ==========
  const reportData = {
    date: targetDate,
    generatedAt: new Date().toISOString(),
    lastUpdatedAt: new Date().toISOString(),
    // Summary stats
    totalGuides: Object.keys(guideData).length,
    guidesWithReports: guidesWithReports,
    totalPassengers: totalPassengers,
    totalBookings: bookings.length,
    unassignedBookings: unassignedBookings.length,
    unassignedPassengers: unassignedPassengers,
    // Aurora (null if no reports yet)
    auroraSummary: auroraSummary,
    auroraReports: auroraRatings.length,
    // Guide details
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
      })),
    };
  }

  // ========== STEP 7: Save to Firestore ==========
  try {
    await db.collection('tour_reports').doc(targetDate).set(reportData, {merge: true});
    console.log(`✅ Report saved to Firestore: tour_reports/${targetDate}`);
  } catch (error) {
    console.error('❌ Error saving to Firestore:', error);
    return {success: false, message: 'Error saving report: ' + error.message, date: targetDate};
  }

  // ========== STEP 8: Create/Update Google Sheet ==========
  let sheetUrl = null;
  try {
    // Check if sheet already exists
    const existingReport = await db.collection('tour_reports').doc(targetDate).get();
    const existingData = existingReport.data() || {};
    const existingSheetId = existingData.spreadsheetId;

    const auth = await getGoogleAuth();
    let spreadsheetId;

    if (existingSheetId) {
      // Update existing sheet
      console.log(`📊 Updating existing sheet: ${existingSheetId}`);
      spreadsheetId = existingSheetId;
      
      // Clear and repopulate
      const sheets = google.sheets({version: 'v4', auth});
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
      // Create new sheet
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
    // Don't fail - Firestore save succeeded
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

/**
 * Cloud Function to proxy Bokun API requests
 * Uses onRequest with CORS for web compatibility
 */
exports.getBookings = onRequest(
  {
    cors: true,  // Enable CORS for all origins
    secrets: ['BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY'],
    invoker: 'public',  // Allow public invocation (still requires Bearer token auth)
  },
  async (req, res) => {
    // Only allow POST
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }

    // Verify Firebase auth token
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      res.status(401).json({ error: 'Unauthorized - missing token' });
      return;
    }

    try {
      const token = authHeader.split('Bearer ')[1];
      const decodedToken = await admin.auth().verifyIdToken(token);
      const uid = decodedToken.uid;
      console.log(`Authenticated user: ${uid}`);

      // Get data from request body (handle both {data: {...}} and direct {...})
      const requestData = req.body.data || req.body;
      const { startDate, endDate } = requestData;

      if (!startDate || !endDate) {
        res.status(400).json({ error: 'startDate and endDate are required' });
        return;
      }

      // Get API keys from secrets
      const accessKey = process.env.BOKUN_ACCESS_KEY;
      const secretKey = process.env.BOKUN_SECRET_KEY;

      if (!accessKey || !secretKey) {
        console.error('Bokun API keys not configured');
        res.status(500).json({ error: 'Bokun API keys not configured' });
        return;
      }

      // Generate Bokun API signature
      const now = new Date();
      const bokunDate = now.toISOString().replace('T', ' ').substring(0, 19);
      const method = 'POST';
      const path = '/booking.json/booking-search';

      // Create HMAC-SHA1 signature
      const message = bokunDate + accessKey + method + path;
      const signature = crypto
        .createHmac('sha1', secretKey)
        .update(message)
        .digest('base64');

      // Prepare request body
      const requestBody = {
        startDateRange: {
          from: startDate,
          to: endDate,
        }
      };

      // Make request to Bokun API
      const result = await new Promise((resolve, reject) => {
        const postData = JSON.stringify(requestBody);

        const options = {
          hostname: 'api.bokun.io',
          path: '/booking.json/booking-search',
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(postData),
            'X-Bokun-AccessKey': accessKey,
            'X-Bokun-Date': bokunDate,
            'X-Bokun-Signature': signature,
          },
        };

        const apiReq = https.request(options, (apiRes) => {
          let data = '';

          apiRes.on('data', (chunk) => {
            data += chunk;
          });

          apiRes.on('end', () => {
            if (apiRes.statusCode >= 200 && apiRes.statusCode < 300) {
              try {
                const jsonData = JSON.parse(data);
                resolve(jsonData);
              } catch (e) {
                reject(new Error(`Failed to parse response: ${e.message}`));
              }
            } else {
              reject(new Error(`Bokun API error: ${apiRes.statusCode} - ${data}`));
            }
          });
        });

        apiReq.on('error', (error) => {
          reject(error);
        });

        apiReq.write(postData);
        apiReq.end();
      });

      console.log(`Successfully fetched ${result.items?.length || 0} bookings for user ${uid}`);

      // Return result wrapped in 'result' for consistency
      res.status(200).json({ result: result });

    } catch (error) {
      console.error('Error in getBookings:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

// ============================================
// FIRESTORE TRIGGER - Generate report when end-of-shift is submitted
// ============================================
exports.onEndOfShiftSubmitted = onDocumentCreated(
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
    console.log(`📝 Aurora: ${data.auroraRating}, Request Reviews: ${data.shouldRequestReviews}`);

    // Generate/update the report for this date
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

// ============================================
// FIRESTORE TRIGGER - Update report when pickups change
// ============================================
// Whenever cached_bookings is updated (which happens when 
// guides are assigned to pickups), regenerate the tour report.
exports.onPickupAssignmentsChanged = onDocumentWritten(
  {
    document: 'cached_bookings/{date}',
    region: 'us-central1',
  },
  async (event) => {
    const date = event.params.date;
    
    // Skip if document was deleted
    if (!event.data.after.exists) {
      console.log(`📋 cached_bookings/${date} was deleted, skipping report update`);
      return null;
    }

    const beforeData = event.data.before.exists ? event.data.before.data() : null;
    const afterData = event.data.after.data();

    // Check if this is just a timestamp update or actual assignment change
    const beforeBookings = beforeData?.bookings || [];
    const afterBookings = afterData?.bookings || [];

    // Quick check: did any assignments actually change?
    const assignmentChanged = hasAssignmentChanged(beforeBookings, afterBookings);
    
    if (!assignmentChanged) {
      console.log(`📋 No assignment changes detected for ${date}, skipping report update`);
      return null;
    }

    console.log(`📋 Pickup assignments changed for ${date}, updating tour report...`);

    // Rate limiting: Don't regenerate more than once per minute
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

// Helper: Check if any guide assignments changed
function hasAssignmentChanged(beforeBookings, afterBookings) {
  // If different lengths, something definitely changed
  if (beforeBookings.length !== afterBookings.length) {
    return true;
  }

  // Create maps of bookingId -> assignedGuideId
  const beforeAssignments = {};
  const afterAssignments = {};

  beforeBookings.forEach((b) => {
    beforeAssignments[b.id || b.bookingId] = b.assignedGuideId || null;
  });

  afterBookings.forEach((b) => {
    afterAssignments[b.id || b.bookingId] = b.assignedGuideId || null;
  });

  // Check if any assignments differ
  for (const bookingId of Object.keys(afterAssignments)) {
    if (beforeAssignments[bookingId] !== afterAssignments[bookingId]) {
      console.log(`📝 Assignment changed for booking ${bookingId}: ${beforeAssignments[bookingId]} → ${afterAssignments[bookingId]}`);
      return true;
    }
  }

  // Check for new bookings
  for (const bookingId of Object.keys(afterAssignments)) {
    if (!(bookingId in beforeAssignments)) {
      console.log(`📝 New booking added: ${bookingId}`);
      return true;
    }
  }

  return false;
}

// ============================================
// FIRESTORE TRIGGER - Update report when bus assignment changes
// ============================================
// This fires when bus is assigned to a guide
exports.onBusAssignmentChanged = onDocumentWritten(
  {
    document: 'bus_guide_assignments/{assignmentId}',
    region: 'us-central1',
  },
  async (event) => {
    // Get date from the document
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

// ============================================
// SCHEDULED FUNCTION - 5am fallback (Iceland time)
// ============================================
// This catches any tours where guides forgot to submit end-of-shift
// Runs at 5am to ensure all late-night tours (ending ~3am) are covered
exports.generateTourReport = onSchedule(
  {
    schedule: '0 5 * * *',  // 5am every day
    timeZone: 'Atlantic/Reykjavik',
    region: 'us-central1',
  },
  async () => {
    console.log('🌅 Starting 5am fallback report generation...');

    // Generate report for YESTERDAY (since 5am is the morning after the tour)
    const now = new Date();
    const yesterday = new Date(now);
    yesterday.setDate(yesterday.getDate() - 1);
    
    // Adjust for Iceland timezone
    const icelandYesterday = new Date(yesterday.toLocaleString('en-US', {timeZone: 'Atlantic/Reykjavik'}));
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

// ============================================
// MANUAL TRIGGER - For testing or regenerating reports
// ============================================
exports.generateTourReportManual = onCall(
  {
    region: 'us-central1',
    invoker: 'public',
  },
  async (request) => {
    console.log('📝 Manual report generation requested');

    const dateParam = request.data?.date;

    // If no date provided, use yesterday (Iceland time) since tours end after midnight
    let targetDate;
    if (dateParam) {
      targetDate = dateParam;
    } else {
      const now = new Date();
      const yesterday = new Date(now);
      yesterday.setDate(yesterday.getDate() - 1);
      const icelandYesterday = new Date(yesterday.toLocaleString('en-US', {timeZone: 'Atlantic/Reykjavik'}));
      targetDate = `${icelandYesterday.getFullYear()}-${String(icelandYesterday.getMonth() + 1).padStart(2, '0')}-${String(icelandYesterday.getDate()).padStart(2, '0')}`;
    }

    console.log(`📅 Generating report for: ${targetDate}`);
    return await generateReport(targetDate);
  }
);

// ============================================
// NOTIFICATION FUNCTIONS
// ============================================

/**
 * Send notification to ADMIN users only
 * Filters users by isAdmin === true (with fallback to role === 'admin' for backwards compatibility)
 */
async function sendNotificationToAdminsOnly(title, body, data = {}) {
  try {
    console.log(`📤 Preparing to send admin-only notification: "${title}"`);
    
    // Get users with isAdmin = true (supports both old role:'admin' and new isAdmin:true)
    const usersSnapshot = await db
      .collection('users')
      .where('isAdmin', '==', true)  // NEW: Check isAdmin field
      .get();

    console.log(`👥 Found ${usersSnapshot.size} admin users in database`);

    // If no admins found with isAdmin field, fallback to role check
    // (for backwards compatibility during migration)
    if (usersSnapshot.empty) {
      console.log('⚠️ No users with isAdmin=true, trying role=admin fallback...');
      const fallbackSnapshot = await db
        .collection('users')
        .where('role', '==', 'admin')
        .get();
      
      if (fallbackSnapshot.empty) {
        console.log('⚠️ No admin users found to send notification');
        return {success: false, message: 'No admin users found'};
      }
      
      // Process fallback results
      const tokens = [];
      const adminNames = [];
      fallbackSnapshot.forEach((doc) => {
        const userData = doc.data();
        if (userData.fcmToken) {
          tokens.push(userData.fcmToken);
          adminNames.push(userData.fullName || userData.email || doc.id);
          console.log(`  ✓ Admin ${userData.fullName || doc.id} has FCM token (fallback)`);
        } else {
          console.log(`  ✗ Admin ${userData.fullName || doc.id} has no FCM token (fallback)`);
        }
      });
      
      if (tokens.length === 0) {
        return {success: false, message: 'No FCM tokens found for admins'};
      }
      
      return await sendPushNotifications(tokens, title, body, data, adminNames);
    }

    const tokens = [];
    const adminNames = [];
    usersSnapshot.forEach((doc) => {
      const userData = doc.data();
      if (userData.fcmToken) {
        tokens.push(userData.fcmToken);
        adminNames.push(userData.fullName || userData.email || doc.id);
        console.log(`  ✓ Admin ${userData.fullName || doc.id} has FCM token`);
      } else {
        console.log(`  ✗ Admin ${userData.fullName || doc.id} has no FCM token`);
      }
    });

    console.log(`📱 Found ${tokens.length} FCM tokens for admin users`);
    console.log(`👤 Admins to notify: ${adminNames.join(', ')}`);

    if (tokens.length === 0) {
      console.log('⚠️ No FCM tokens found for admin users');
      return {success: false, message: 'No FCM tokens found for admins'};
    }

    return await sendPushNotifications(tokens, title, body, data, adminNames);
  } catch (error) {
    console.error('❌ Error sending notification to admins:', error);
    return {success: false, error: error.message};
  }
}

/**
 * Helper function to send push notifications
 */
async function sendPushNotifications(tokens, title, body, data, recipientNames) {
  const messages = tokens.map((token) => ({
    notification: {
      title: title,
      body: body,
    },
    data: {
      ...Object.keys(data).reduce((acc, key) => {
        acc[key] = String(data[key]);
        return acc;
      }, {}),
      click_action: 'FLUTTER_NOTIFICATION_CLICK',
    },
    token: token,
    android: {
      priority: 'high',
      notification: {
        channelId: 'aurora_viking_staff',
        sound: 'default',
      },
    },
    apns: {
      payload: {
        aps: {
          sound: 'default',
        },
      },
    },
  }));

  const response = await admin.messaging().sendEach(messages);

  console.log(`✅ Notification sent to ${response.successCount} admin(s): ${recipientNames.join(', ')}`);
  if (response.failureCount > 0) {
    console.log(`⚠️ Failed to send to ${response.failureCount} admin(s)`);
  }

  return {
    success: true,
    sent: response.successCount,
    failed: response.failureCount,
    recipients: recipientNames,
  };
}

/**
 * Send push notification to all users
 */
async function sendNotificationToAdmins(title, body, data = {}) {
  try {
    console.log(`📤 Preparing to send notification: "${title}" - "${body}"`);
    
    // Get all users (changed from admin-only to all users)
    const usersSnapshot = await db
      .collection('users')
      .get();

    console.log(`👥 Found ${usersSnapshot.size} users in database`);

    if (usersSnapshot.empty) {
      console.log('⚠️ No users found to send notification');
      return {success: false, message: 'No users found'};
    }

    const tokens = [];
    usersSnapshot.forEach((doc) => {
      const userData = doc.data();
      if (userData.fcmToken) {
        tokens.push(userData.fcmToken);
        console.log(`  ✓ User ${doc.id} has FCM token`);
      } else {
        console.log(`  ✗ User ${doc.id} (${userData.email || 'no email'}) has no FCM token`);
      }
    });

    console.log(`📱 Found ${tokens.length} FCM tokens out of ${usersSnapshot.size} users`);

    if (tokens.length === 0) {
      console.log('⚠️ No FCM tokens found for users - notifications cannot be sent');
      return {success: false, message: 'No FCM tokens found'};
    }

    // Send notification to all admin tokens
    const messages = tokens.map((token) => ({
      notification: {
        title: title,
        body: body,
      },
      data: {
        ...Object.keys(data).reduce((acc, key) => {
          acc[key] = String(data[key]);
          return acc;
        }, {}),
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      token: token,
      android: {
        priority: 'high',
        notification: {
          channelId: 'aurora_viking_staff',
          sound: 'default',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
          },
        },
      },
    }));

    const batch = admin.messaging().sendEach(messages);
    const response = await batch;

    console.log(`✅ Notification sent to ${response.successCount} user(s)`);
    if (response.failureCount > 0) {
      console.log(`⚠️ Failed to send to ${response.failureCount} user(s)`);
    }

    return {
      success: true,
      sent: response.successCount,
      failed: response.failureCount,
    };
  } catch (error) {
    console.error('❌ Error sending notification to admins:', error);
    return {success: false, error: error.message};
  }
}

/**
 * Get booking details from cached bookings
 */
async function getBookingDetails(bookingId, date) {
  try {
    const cacheDoc = await db.collection('cached_bookings').doc(date).get();
    if (!cacheDoc.exists) {
      return null;
    }

    const cachedBookings = cacheDoc.data().bookings || [];
    const booking = cachedBookings.find((b) => b.id === bookingId);
    return booking || null;
  } catch (error) {
    console.error('❌ Error getting booking details:', error);
    return null;
  }
}

/**
 * Get guide assignment for a booking
 */
async function getGuideAssignment(bookingId, date) {
  try {
    // Try individual assignment format first (date_bookingId)
    const assignmentDoc = await db.collection('pickup_assignments')
      .doc(`${date}_${bookingId}`)
      .get();
    
    if (assignmentDoc.exists) {
      const data = assignmentDoc.data();
      return {
        guideId: data.guideId,
        guideName: data.guideName,
      };
    }

    // Try querying by bookingId
    const querySnapshot = await db.collection('pickup_assignments')
      .where('date', '==', date)
      .where('bookingId', '==', bookingId)
      .limit(1)
      .get();
    
    if (!querySnapshot.empty) {
      const data = querySnapshot.docs[0].data();
      return {
        guideId: data.guideId,
        guideName: data.guideName,
      };
    }

    return null;
  } catch (error) {
    console.error('❌ Error getting guide assignment:', error);
    return null;
  }
}

/**
 * Check if all pickups are complete for a guide
 */
async function areAllPickupsCompleteForGuide(guideId, date) {
  try {
    // Get all bookings assigned to this guide for this date
    const assignmentsSnapshot = await db.collection('pickup_assignments')
      .where('date', '==', date)
      .where('guideId', '==', guideId)
      .get();

    if (assignmentsSnapshot.empty) {
      console.log(`⚠️ No assignments found for guide ${guideId} on ${date}`);
      return false;
    }

    const bookingIds = [];
    assignmentsSnapshot.forEach((doc) => {
      const data = doc.data();
      if (data.bookingId) {
        bookingIds.push(data.bookingId);
      } else if (data.bookings && Array.isArray(data.bookings)) {
        // Bulk assignment format - extract booking IDs
        data.bookings.forEach((booking) => {
          if (booking.id) {
            bookingIds.push(booking.id);
          }
        });
      }
    });

    if (bookingIds.length === 0) {
      console.log(`⚠️ No booking IDs found for guide ${guideId} on ${date}`);
      return false;
    }

    console.log(`🔍 Checking ${bookingIds.length} bookings for guide ${guideId}`);

    // Check status of each booking
    const statusChecks = bookingIds.map(async (bid) => {
      const statusDoc = await db.collection('booking_status')
        .doc(`${date}_${bid}`)
        .get();
      
      if (!statusDoc.exists) {
        return false; // No status yet, not complete
      }

      const status = statusDoc.data();
      const isArrived = status.isArrived === true;
      const isNoShow = status.isNoShow === true;
      
      // Consider complete if arrived OR marked as no-show
      return isArrived || isNoShow;
    });

    const results = await Promise.all(statusChecks);
    const allComplete = results.every((complete) => complete === true);
    const completedCount = results.filter((complete) => complete === true).length;

    console.log(`📊 Guide ${guideId}: ${completedCount}/${bookingIds.length} pickups complete`);

    return allComplete;
  } catch (error) {
    console.error('❌ Error checking if all pickups are complete:', error);
    return false;
  }
}

/**
 * Firestore trigger: Send notification when pickup is completed (isArrived becomes true)
 */
exports.onPickupCompleted = onDocumentWritten(
  {
    document: 'booking_status/{documentId}',
    region: 'us-central1',
  },
  async (event) => {
    const change = event.data;
    if (!change) {
      console.log('⚠️ No change data in event');
      return;
    }

    const before = change.before?.data();
    const after = change.after?.data();
    const documentId = event.params.documentId;
    
    console.log('🔔 onPickupCompleted triggered for document:', documentId);
    console.log('📊 Before data:', JSON.stringify(before));
    console.log('📊 After data:', JSON.stringify(after));

    // Check if document was deleted
    if (!change.after?.exists) {
      console.log('⚠️ Document was deleted, skipping');
      return;
    }

    // Extract date and bookingId from document ID (format: YYYY-MM-DD_bookingId)
    const parts = documentId.split('_');
    console.log(`🔍 Parsing document ID: "${documentId}" -> parts: [${parts.join(', ')}]`);
    
    if (parts.length < 2) {
      console.log(`⚠️ Document ID doesn't have enough parts (need at least 2 for date_bookingId), got ${parts.length}`);
      return;
    }
    const date = parts[0]; // Already YYYY-MM-DD format
    const bookingId = parts.slice(1).join('_'); // Rest is booking ID
    console.log(`✅ Parsed: date="${date}", bookingId="${bookingId}"`);

    // Check if isArrived changed from false/undefined to true
    const wasArrived = before?.isArrived === true;
    const isNowArrived = after?.isArrived === true;
    
    console.log(`🔍 Checking pickup status: wasArrived=${wasArrived}, isNowArrived=${isNowArrived}`);

    if (!wasArrived && isNowArrived) {
      console.log(`✅ Pickup completed detected for booking ${bookingId} on ${date}`);

      // Get guide assignment for this booking
      const guideAssignment = await getGuideAssignment(bookingId, date);
      
      if (!guideAssignment) {
        console.log('⚠️ No guide assignment found for this booking, skipping notification');
        return;
      }

      console.log(`👤 Booking assigned to guide: ${guideAssignment.guideName} (${guideAssignment.guideId})`);

      // Check if all pickups are complete for this guide
      const allComplete = await areAllPickupsCompleteForGuide(guideAssignment.guideId, date);

      if (allComplete) {
        console.log(`🎉 All pickups complete for guide ${guideAssignment.guideName}! Sending notification.`);

        // Get booking details
        const booking = await getBookingDetails(bookingId, date);
        const customerName = booking?.customerFullName || booking?.customerName || 'Unknown Customer';

        // Send notification to all users
        await sendNotificationToAdmins(
          '🎉 All Pickups Complete',
          `${guideAssignment.guideName} has finished all pickups for ${date}`,
          {
            type: 'all_pickups_complete',
            guideId: guideAssignment.guideId,
            guideName: guideAssignment.guideName,
            date: date,
            lastBookingId: bookingId,
            lastCustomerName: customerName,
          }
        );
      } else {
        console.log(`ℹ️ Not all pickups complete yet for guide ${guideAssignment.guideName}, skipping notification`);
      }
    } else {
      console.log('ℹ️ Pickup status did not change from false to true, skipping notification');
    }
  }
);

/**
 * Firestore trigger: Send notification when no-show is marked
 */
exports.onNoShowMarked = onDocumentWritten(
  {
    document: 'booking_status/{documentId}',
    region: 'us-central1',
  },
  async (event) => {
    const change = event.data;
    if (!change) {
      console.log('⚠️ No change data in event');
      return;
    }

    const before = change.before?.data();
    const after = change.after?.data();
    const documentId = event.params.documentId;
    
    console.log('🔔 onNoShowMarked triggered for document:', documentId);
    console.log('📊 Before data:', JSON.stringify(before));
    console.log('📊 After data:', JSON.stringify(after));

    // Check if document was deleted
    if (!change.after?.exists) {
      console.log('⚠️ Document was deleted, skipping');
      return;
    }

    // Extract date and bookingId from document ID
    const parts = documentId.split('_');
    console.log(`🔍 Parsing document ID: "${documentId}" -> parts: [${parts.join(', ')}]`);
    
    if (parts.length < 2) {
      console.log(`⚠️ Document ID doesn't have enough parts (need at least 2 for date_bookingId), got ${parts.length}`);
      return;
    }
    const date = parts[0]; // Already YYYY-MM-DD format
    const bookingId = parts.slice(1).join('_'); // Rest is booking ID
    console.log(`✅ Parsed: date="${date}", bookingId="${bookingId}"`);

    // Check if isNoShow changed from false/undefined to true
    const wasNoShow = before?.isNoShow === true;
    const isNowNoShow = after?.isNoShow === true;
    
    console.log(`🔍 Checking no-show status: wasNoShow=${wasNoShow}, isNowNoShow=${isNowNoShow}`);

    if (!wasNoShow && isNowNoShow) {
      console.log(`✅ No-show detected for booking ${bookingId} on ${date}`);

      // Get guide assignment for this booking
      const guideAssignment = await getGuideAssignment(bookingId, date);
      
      if (!guideAssignment) {
        console.log('⚠️ No guide assignment found for this booking, skipping notification');
        return;
      }

      console.log(`👤 Booking assigned to guide: ${guideAssignment.guideName} (${guideAssignment.guideId})`);

      // Check if all pickups are complete for this guide (including no-shows)
      const allComplete = await areAllPickupsCompleteForGuide(guideAssignment.guideId, date);

      if (allComplete) {
        console.log(`🎉 All pickups complete for guide ${guideAssignment.guideName}! Sending notification.`);

        // Get booking details
        const booking = await getBookingDetails(bookingId, date);
        const customerName = booking?.customerFullName || booking?.customerName || 'Unknown Customer';

        // Send notification to all users
        await sendNotificationToAdmins(
          '🎉 All Pickups Complete',
          `${guideAssignment.guideName} has finished all pickups for ${date}`,
          {
            type: 'all_pickups_complete',
            guideId: guideAssignment.guideId,
            guideName: guideAssignment.guideName,
            date: date,
            lastBookingId: bookingId,
            lastCustomerName: customerName,
          }
        );
      } else {
        console.log(`ℹ️ Not all pickups complete yet for guide ${guideAssignment.guideName}, skipping notification`);
      }
    } else {
      console.log('ℹ️ No-show status did not change from false to true, skipping notification');
    }
  }
);

// ============================================
// AURORA SIGHTING NOTIFICATION FUNCTION
// ============================================

/**
 * Get a Google Maps link for coordinates
 */
function getGoogleMapsLink(latitude, longitude) {
  if (!latitude || !longitude) return null;
  return `https://maps.google.com/?q=${latitude},${longitude}`;
}

/**
 * Get emoji for aurora level
 */
function getAuroraEmoji(level) {
  const emojis = {
    'weak': '🌌',
    'medium': '✨',
    'strong': '🔥',
    'exceptional': '🤯',
  };
  return emojis[level] || '🌌';
}

/**
 * Firestore trigger: Send notification when aurora sighting is reported
 * Triggers on NEW documents in aurora_sightings collection
 */
exports.onAuroraSighting = onDocumentWritten(
  {
    document: 'aurora_sightings/{sightingId}',
    region: 'us-central1',
  },
  async (event) => {
    const sightingId = event.params.sightingId;
    
    console.log('🌌 onAuroraSighting triggered for document:', sightingId);
    
    // Only process NEW documents (not updates or deletes)
    if (!event.data.after.exists) {
      console.log('⚠️ Document was deleted, skipping');
      return;
    }
    
    // Check if this is a new document (before didn't exist)
    if (event.data.before.exists) {
      console.log('ℹ️ Document was updated (not created), skipping');
      return;
    }

    const sightingData = event.data.after.data();
    
    console.log('📊 Sighting data:', JSON.stringify(sightingData));

    // Check if already processed (prevent duplicate notifications)
    if (sightingData.processed === true) {
      console.log('ℹ️ Sighting already processed, skipping');
      return;
    }

    const guideName = sightingData.guideName || 'A guide';
    const level = sightingData.level || 'unknown';
    const levelLabel = sightingData.levelLabel || level;
    const emoji = getAuroraEmoji(level);
    const latitude = sightingData.latitude;
    const longitude = sightingData.longitude;
    const hasLocation = sightingData.hasLocation === true;

    // Build notification body
    let notificationBody = `${guideName} spotted ${levelLabel.toLowerCase()} aurora!`;
    
    if (hasLocation && latitude && longitude) {
      // Add approximate location description
      notificationBody += ` 📍 Location available`;
    }

    // Build data payload
    const notificationData = {
      type: 'aurora_sighting',
      sightingId: sightingId,
      guideId: sightingData.guideId || '',
      guideName: guideName,
      level: level,
      levelLabel: levelLabel,
      timestamp: sightingData.timestamp?.toDate?.()?.toISOString() || new Date().toISOString(),
    };

    if (hasLocation && latitude && longitude) {
      notificationData.latitude = String(latitude);
      notificationData.longitude = String(longitude);
      notificationData.mapsLink = getGoogleMapsLink(latitude, longitude);
    }

    if (sightingData.busId) {
      notificationData.busId = sightingData.busId;
    }

    // Send notification to ADMINS ONLY
    console.log(`🌌 Sending ${emoji} ${levelLabel} aurora alert from ${guideName}`);
    
    const result = await sendNotificationToAdminsOnly(
      `${emoji} ${levelLabel} Aurora Spotted!`,
      notificationBody,
      notificationData
    );

    // Mark as processed to prevent duplicate notifications
    try {
      await db.collection('aurora_sightings').doc(sightingId).update({
        processed: true,
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
        notificationResult: result,
      });
      console.log('✅ Sighting marked as processed');
    } catch (updateError) {
      console.error('⚠️ Failed to mark sighting as processed:', updateError);
    }

    return result;
  }
);

