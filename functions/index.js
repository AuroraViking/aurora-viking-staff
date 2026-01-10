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
      // Continue anyway - maybe we have assignments without cached bookings
    } else {
      const cachedData = cacheDoc.data();
      bookings = cachedData.bookings || [];
      console.log(`📋 Found ${bookings.length} bookings in cached_bookings`);
    }
  } catch (error) {
    console.log('⚠️ Could not fetch cached_bookings:', error.message);
    // Continue - we'll try to use pickup_assignments
  }

  // ========== STEP 1.5: Get pickup_assignments (SOURCE OF TRUTH!) ==========
  // This is the fix - read assignments from the dedicated collection
  // These persist even when cached_bookings gets refreshed
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
  // Apply pickup_assignments to bookings (this is the key fix!)
  bookings = bookings.map((booking) => {
    const bookingId = booking.id || booking.bookingId;
    const assignment = pickupAssignments[bookingId];
    
    if (assignment) {
      // Use assignment from pickup_assignments (source of truth)
      return {
        ...booking,
        assignedGuideId: assignment.guideId,
        assignedGuideName: assignment.guideName,
      };
    } else if (booking.assignedGuideId) {
      // Keep existing assignment from cached_bookings
      return booking;
    } else {
      // No assignment found
      return booking;
    }
  });

  // Log how many bookings now have assignments
  const assignedCount = bookings.filter(b => b.assignedGuideId).length;
  console.log(`✅ After merging: ${assignedCount}/${bookings.length} bookings have guide assignments`);

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

  // Count total no-shows
  const totalNoShows = bookings.filter(b => b.isNoShow === true).length;

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
    totalNoShows: totalNoShows,
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

    // SAFETY: Detect dangerous "fresh fetch" that lost all assignments
    const beforeAssignedCount = beforeBookings.filter(b => b.assignedGuideId).length;
    const afterAssignedCount = afterBookings.filter(b => b.assignedGuideId).length;
    
    if (beforeAssignedCount > 0 && afterAssignedCount === 0 && afterBookings.length > 0) {
      console.log(`⚠️ DANGER: cached_bookings refresh lost all ${beforeAssignedCount} assignments!`);
      console.log(`⚠️ This looks like a fresh API fetch - NOT regenerating report to preserve existing data`);
      console.log(`⚠️ The pickup_assignments collection still has the real assignments`);
      return null;
    }

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

// ============================================
// UNIFIED INBOX - MESSAGING FUNCTIONS
// ============================================

/**
 * Extracts booking references from message content
 * Looks for patterns like AV-12345, av-12345, etc.
 */
function extractBookingReferences(content) {
  if (!content) return [];
  const regex = /\b(AV|av)-\d+\b/gi;
  const matches = content.match(regex);
  return matches ? matches.map(m => m.toUpperCase()) : [];
}

/**
 * Find or create customer from email/phone
 */
async function findOrCreateCustomer(channel, identifier, name) {
  const customersRef = db.collection('customers');
  
  // Build query based on channel
  let query;
  if (channel === 'gmail') {
    query = customersRef.where('channels.gmail', '==', identifier);
  } else if (channel === 'whatsapp') {
    query = customersRef.where('channels.whatsapp', '==', identifier);
  } else if (channel === 'wix') {
    query = customersRef.where('channels.wix', '==', identifier);
  }
  
  const snapshot = await query.limit(1).get();
  
  if (!snapshot.empty) {
    // Update last contact
    const customerDoc = snapshot.docs[0];
    await customerDoc.ref.update({
      lastContact: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return customerDoc.id;
  }
  
  // Extract name from email if not provided
  let extractedName = name;
  if (!extractedName && channel === 'gmail') {
    extractedName = identifier.split('@')[0].replace(/[._]/g, ' ');
    // Capitalize each word
    extractedName = extractedName.split(' ')
      .map(w => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase())
      .join(' ');
  }
  
  // Create new customer
  const newCustomer = {
    name: extractedName || identifier,
    email: channel === 'gmail' ? identifier : null,
    phone: channel === 'whatsapp' ? identifier : null,
    channels: {
      gmail: channel === 'gmail' ? identifier : null,
      whatsapp: channel === 'whatsapp' ? identifier : null,
      wix: channel === 'wix' ? identifier : null,
    },
    totalBookings: 0,
    upcomingBookings: [],
    pastBookings: [],
    language: 'en',
    vipStatus: false,
    pastInteractions: 0,
    averageResponseTime: 0,
    commonRequests: [],
    firstContact: admin.firestore.FieldValue.serverTimestamp(),
    lastContact: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  
  const docRef = await customersRef.add(newCustomer);
  console.log(`👤 Created new customer: ${newCustomer.name} (${docRef.id})`);
  return docRef.id;
}

/**
 * Find or create conversation
 */
async function findOrCreateConversation(customerId, channel, threadId, subject, messagePreview) {
  const conversationsRef = db.collection('conversations');
  
  // Try to find existing conversation by thread ID (for Gmail) or recent active conversation
  let snapshot;
  if (channel === 'gmail' && threadId) {
    // For Gmail, match by thread ID
    snapshot = await conversationsRef
      .where('customerId', '==', customerId)
      .where('channel', '==', channel)
      .where('channelMetadata.gmail.threadId', '==', threadId)
      .limit(1)
      .get();
  }
  
  // If not found, check for recent active conversation (within last 24 hours)
  if (!snapshot || snapshot.empty) {
    const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
    snapshot = await conversationsRef
      .where('customerId', '==', customerId)
      .where('channel', '==', channel)
      .where('status', '==', 'active')
      .where('lastMessageAt', '>=', oneDayAgo)
      .limit(1)
      .get();
  }
  
  if (snapshot && !snapshot.empty) {
    // Update existing conversation
    const convDoc = snapshot.docs[0];
    await convDoc.ref.update({
      lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
      lastMessagePreview: messagePreview.substring(0, 100),
      unreadCount: admin.firestore.FieldValue.increment(1),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return convDoc.id;
  }
  
  // Create new conversation
  const newConversation = {
    customerId,
    channel,
    subject: subject || null,
    bookingIds: [],
    messageIds: [],
    status: 'active',
    lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
    lastMessagePreview: messagePreview.substring(0, 100),
    unreadCount: 1,
    channelMetadata: channel === 'gmail' && threadId ? { gmail: { threadId } } : {},
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  
  const docRef = await conversationsRef.add(newConversation);
  console.log(`💬 Created new conversation: ${docRef.id}`);
  return docRef.id;
}

/**
 * Process incoming Gmail message (triggered by Pub/Sub - placeholder)
 * In production, this would be connected to Gmail Push Notifications
 */
exports.processGmailMessage = onCall(
  {
    region: 'us-central1',
    invoker: 'public',
  },
  async (request) => {
    console.log('📧 Processing Gmail message');
    
    const { messageId, threadId, from, to, subject, content, receivedAt } = request.data;
    
    if (!from || !content) {
      console.log('⚠️ Missing required fields');
      return { success: false, error: 'Missing required fields: from, content' };
    }
    
    try {
      // Extract booking references
      const detectedBookingNumbers = extractBookingReferences(content + ' ' + (subject || ''));
      console.log(`🔍 Detected booking refs: ${detectedBookingNumbers.join(', ') || 'none'}`);
      
      // Find or create customer
      const customerId = await findOrCreateCustomer('gmail', from, null);
      
      // Find or create conversation
      const conversationId = await findOrCreateConversation(
        customerId,
        'gmail',
        threadId || null,
        subject || null,
        content
      );
      
      // Create message document
      const messageData = {
        conversationId,
        customerId,
        channel: 'gmail',
        direction: 'inbound',
        subject: subject || null,
        content,
        timestamp: receivedAt ? new Date(receivedAt) : admin.firestore.FieldValue.serverTimestamp(),
        channelMetadata: {
          gmail: {
            threadId: threadId || '',
            messageId: messageId || '',
            from,
            to: Array.isArray(to) ? to : [to || 'info@auroraviking.is'],
          },
        },
        bookingIds: [],
        detectedBookingNumbers,
        status: 'pending',
        flaggedForReview: false,
        priority: 'normal',
      };
      
      const msgRef = await db.collection('messages').add(messageData);
      console.log(`📨 Message created: ${msgRef.id}`);
      
      // Update conversation with message ID
      await db.collection('conversations').doc(conversationId).update({
        messageIds: admin.firestore.FieldValue.arrayUnion(msgRef.id),
        bookingIds: admin.firestore.FieldValue.arrayUnion(...detectedBookingNumbers),
      });
      
      return {
        success: true,
        messageId: msgRef.id,
        conversationId,
        customerId,
        detectedBookingNumbers,
      };
    } catch (error) {
      console.error('❌ Error processing Gmail message:', error);
      return { success: false, error: error.message };
    }
  }
);

/**
 * Send message via channel (currently supports Gmail placeholder)
 */
exports.sendInboxMessage = onCall(
  {
    region: 'us-central1',
    invoker: 'public',
  },
  async (request) => {
    console.log('📤 Sending inbox message');
    
    // Verify authentication
    if (!request.auth) {
      return { success: false, error: 'Authentication required' };
    }
    
    const { conversationId, content, channel } = request.data;
    
    if (!conversationId || !content) {
      return { success: false, error: 'Missing required fields: conversationId, content' };
    }
    
    try {
      // Get conversation details
      const convDoc = await db.collection('conversations').doc(conversationId).get();
      if (!convDoc.exists) {
        return { success: false, error: 'Conversation not found' };
      }
      
      const conversation = convDoc.data();
      
      // Get customer details
      const customerDoc = await db.collection('customers').doc(conversation.customerId).get();
      if (!customerDoc.exists) {
        return { success: false, error: 'Customer not found' };
      }
      
      const customer = customerDoc.data();
      
      // Build outbound message
      const messageData = {
        conversationId,
        customerId: conversation.customerId,
        channel: channel || conversation.channel,
        direction: 'outbound',
        content,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        channelMetadata: {},
        bookingIds: [],
        detectedBookingNumbers: extractBookingReferences(content),
        status: 'responded',
        handledBy: request.auth.uid,
        handledAt: admin.firestore.FieldValue.serverTimestamp(),
        flaggedForReview: false,
        priority: 'normal',
      };
      
      // Build channel metadata
      if ((channel || conversation.channel) === 'gmail') {
        messageData.channelMetadata.gmail = {
          to: [customer.email || customer.channels?.gmail],
          from: 'info@auroraviking.is',
          threadId: conversation.channelMetadata?.gmail?.threadId || '',
        };
        
        // TODO: Actually send via Gmail API
        // For now, just store the message
        console.log('📧 Gmail send placeholder - message stored but not sent via API');
      }
      
      // Store message
      const msgRef = await db.collection('messages').add(messageData);
      console.log(`📨 Outbound message created: ${msgRef.id}`);
      
      // Update conversation
      await convDoc.ref.update({
        lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
        lastMessagePreview: content.substring(0, 100),
        unreadCount: 0,
        messageIds: admin.firestore.FieldValue.arrayUnion(msgRef.id),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      return {
        success: true,
        messageId: msgRef.id,
      };
    } catch (error) {
      console.error('❌ Error sending message:', error);
      return { success: false, error: error.message };
    }
  }
);

/**
 * Mark conversation as read
 */
exports.markConversationRead = onCall(
  {
    region: 'us-central1',
    invoker: 'public',
  },
  async (request) => {
    if (!request.auth) {
      return { success: false, error: 'Authentication required' };
    }
    
    const { conversationId } = request.data;
    
    if (!conversationId) {
      return { success: false, error: 'Missing conversationId' };
    }
    
    try {
      await db.collection('conversations').doc(conversationId).update({
        unreadCount: 0,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      return { success: true };
    } catch (error) {
      console.error('❌ Error marking conversation as read:', error);
      return { success: false, error: error.message };
    }
  }
);

/**
 * Update conversation status (resolve/archive)
 */
exports.updateConversationStatus = onCall(
  {
    region: 'us-central1',
    invoker: 'public',
  },
  async (request) => {
    if (!request.auth) {
      return { success: false, error: 'Authentication required' };
    }
    
    const { conversationId, status } = request.data;
    
    if (!conversationId || !status) {
      return { success: false, error: 'Missing conversationId or status' };
    }
    
    if (!['active', 'resolved', 'archived'].includes(status)) {
      return { success: false, error: 'Invalid status. Must be: active, resolved, or archived' };
    }
    
    try {
      await db.collection('conversations').doc(conversationId).update({
        status,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      return { success: true };
    } catch (error) {
      console.error('❌ Error updating conversation status:', error);
      return { success: false, error: error.message };
    }
  }
);

/**
 * Create test message (for development/testing)
 * Directly creates test data in Firestore
 */
exports.createTestInboxMessage = onCall(
  {
    region: 'us-central1',
    invoker: 'public',  // Required for Flutter SDK to call this function
  },
  async (request) => {
    // Log auth status for debugging
    console.log('🧪 createTestInboxMessage called');
    console.log('🧪 Auth present:', request.auth ? 'yes' : 'no');
    if (request.auth) {
      console.log('🧪 User ID:', request.auth.uid);
    }
    
    // For test function, we'll allow unauthenticated calls during development
    // In production, you'd want to check auth
    console.log('🧪 Creating test inbox message...');
    
    const testEmail = request.data?.email || 'test@example.com';
    const testContent = request.data?.content || 'Hi, I have a question about my booking AV-12345. Can you help me?';
    const testSubject = request.data?.subject || 'Question about my booking';
    
    try {
      // Extract booking references
      const detectedBookingNumbers = extractBookingReferences(testContent + ' ' + testSubject);
      console.log(`🔍 Detected booking refs: ${detectedBookingNumbers.join(', ') || 'none'}`);
      
      // Find or create customer
      const customerId = await findOrCreateCustomer('gmail', testEmail, null);
      
      // Find or create conversation
      const threadId = `thread-${Date.now()}`;
      const conversationId = await findOrCreateConversation(
        customerId,
        'gmail',
        threadId,
        testSubject,
        testContent
      );
      
      // Create message document
      const messageData = {
        conversationId,
        customerId,
        channel: 'gmail',
        direction: 'inbound',
        subject: testSubject,
        content: testContent,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        channelMetadata: {
          gmail: {
            threadId: threadId,
            messageId: `test-${Date.now()}`,
            from: testEmail,
            to: ['info@auroraviking.is'],
          },
        },
        bookingIds: [],
        detectedBookingNumbers,
        status: 'pending',
        flaggedForReview: false,
        priority: 'normal',
      };
      
      const msgRef = await db.collection('messages').add(messageData);
      console.log(`📨 Test message created: ${msgRef.id}`);
      
      // Update conversation with message ID
      await db.collection('conversations').doc(conversationId).update({
        messageIds: admin.firestore.FieldValue.arrayUnion(msgRef.id),
        bookingIds: admin.firestore.FieldValue.arrayUnion(...detectedBookingNumbers),
      });
      
      return {
        success: true,
        messageId: msgRef.id,
        conversationId,
        customerId,
        detectedBookingNumbers,
      };
    } catch (error) {
      console.error('❌ Error creating test message:', error);
      return { success: false, error: error.message };
    }
  }
);

// ============================================
// GMAIL INTEGRATION
// ============================================

const GMAIL_REDIRECT_URI = 'https://us-central1-aurora-viking-staff.cloudfunctions.net/gmailOAuthCallback';
const GMAIL_SCOPES = [
  'https://www.googleapis.com/auth/gmail.readonly',
  'https://www.googleapis.com/auth/gmail.send',
  'https://www.googleapis.com/auth/gmail.modify',
];

/**
 * Get Gmail OAuth2 client
 */
function getGmailOAuth2Client(clientId, clientSecret) {
  return new google.auth.OAuth2(clientId, clientSecret, GMAIL_REDIRECT_URI);
}

/**
 * Store Gmail tokens in Firestore
 */
async function storeGmailTokens(email, tokens) {
  await db.collection('system').doc('gmail_tokens').set({
    email,
    accessToken: tokens.access_token,
    refreshToken: tokens.refresh_token,
    expiryDate: tokens.expiry_date,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  console.log(`✅ Gmail tokens stored for ${email}`);
}

/**
 * Get Gmail tokens from Firestore
 */
async function getGmailTokens() {
  const doc = await db.collection('system').doc('gmail_tokens').get();
  if (!doc.exists) {
    return null;
  }
  return doc.data();
}

/**
 * Get authenticated Gmail client
 */
async function getGmailClient(clientId, clientSecret) {
  const tokens = await getGmailTokens();
  if (!tokens) {
    throw new Error('Gmail not authorized. Please complete OAuth flow first.');
  }
  
  const oauth2Client = getGmailOAuth2Client(clientId, clientSecret);
  oauth2Client.setCredentials({
    access_token: tokens.accessToken,
    refresh_token: tokens.refreshToken,
    expiry_date: tokens.expiryDate,
  });
  
  // Handle token refresh
  oauth2Client.on('tokens', async (newTokens) => {
    console.log('🔄 Gmail tokens refreshed');
    await storeGmailTokens(tokens.email, {
      access_token: newTokens.access_token || tokens.accessToken,
      refresh_token: newTokens.refresh_token || tokens.refreshToken,
      expiry_date: newTokens.expiry_date,
    });
  });
  
  return google.gmail({ version: 'v1', auth: oauth2Client });
}

/**
 * Gmail OAuth - Step 1: Generate authorization URL
 * Visit this URL to authorize the Gmail account
 */
exports.gmailOAuthStart = onRequest(
  {
    region: 'us-central1',
    secrets: ['GMAIL_CLIENT_ID', 'GMAIL_CLIENT_SECRET'],
    invoker: 'public',
  },
  async (req, res) => {
    const clientId = process.env.GMAIL_CLIENT_ID;
    const clientSecret = process.env.GMAIL_CLIENT_SECRET;
    
    const oauth2Client = getGmailOAuth2Client(clientId, clientSecret);
    
    const authUrl = oauth2Client.generateAuthUrl({
      access_type: 'offline',
      scope: GMAIL_SCOPES,
      prompt: 'consent', // Force to get refresh token
    });
    
    res.send(`
      <html>
        <head>
          <title>Aurora Viking - Gmail Authorization</title>
          <style>
            body { font-family: Arial, sans-serif; max-width: 600px; margin: 50px auto; padding: 20px; }
            .btn { display: inline-block; background: #4285f4; color: white; padding: 12px 24px; 
                   text-decoration: none; border-radius: 4px; font-size: 16px; }
            .btn:hover { background: #3367d6; }
          </style>
        </head>
        <body>
          <h1>🌌 Aurora Viking - Gmail Setup</h1>
          <p>Click the button below to authorize Gmail access for the Unified Inbox.</p>
          <p>This will allow the app to:</p>
          <ul>
            <li>Read incoming emails</li>
            <li>Send replies on your behalf</li>
            <li>Mark emails as read</li>
          </ul>
          <p><a href="${authUrl}" class="btn">Authorize Gmail Access</a></p>
        </body>
      </html>
    `);
  }
);

/**
 * Gmail OAuth - Step 2: Handle callback and store tokens
 */
exports.gmailOAuthCallback = onRequest(
  {
    region: 'us-central1',
    secrets: ['GMAIL_CLIENT_ID', 'GMAIL_CLIENT_SECRET'],
    invoker: 'public',
  },
  async (req, res) => {
    const code = req.query.code;
    
    if (!code) {
      res.status(400).send('Missing authorization code');
      return;
    }
    
    try {
      const clientId = process.env.GMAIL_CLIENT_ID;
      const clientSecret = process.env.GMAIL_CLIENT_SECRET;
      
      const oauth2Client = getGmailOAuth2Client(clientId, clientSecret);
      const { tokens } = await oauth2Client.getToken(code);
      
      oauth2Client.setCredentials(tokens);
      
      // Get the email address
      const gmail = google.gmail({ version: 'v1', auth: oauth2Client });
      const profile = await gmail.users.getProfile({ userId: 'me' });
      const email = profile.data.emailAddress;
      
      // Store tokens
      await storeGmailTokens(email, tokens);
      
      // Initialize last check timestamp
      await db.collection('system').doc('gmail_sync').set({
        lastCheckTimestamp: Date.now(),
        lastHistoryId: null,
        email: email,
        setupAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      res.send(`
        <html>
          <head>
            <title>Gmail Connected!</title>
            <style>
              body { font-family: Arial, sans-serif; max-width: 600px; margin: 50px auto; padding: 20px; text-align: center; }
              .success { color: #34a853; font-size: 48px; }
            </style>
          </head>
          <body>
            <div class="success">✅</div>
            <h1>Gmail Connected Successfully!</h1>
            <p>Email: <strong>${email}</strong></p>
            <p>The Aurora Viking Staff app will now receive emails from this inbox.</p>
            <p>You can close this window.</p>
          </body>
        </html>
      `);
    } catch (error) {
      console.error('OAuth callback error:', error);
      res.status(500).send(`
        <html>
          <body>
            <h1>❌ Error</h1>
            <p>${error.message}</p>
          </body>
        </html>
      `);
    }
  }
);

/**
 * Poll Gmail for new messages (runs every 2 minutes)
 */
exports.pollGmailInbox = onSchedule(
  {
    schedule: 'every 2 minutes',
    region: 'us-central1',
    secrets: ['GMAIL_CLIENT_ID', 'GMAIL_CLIENT_SECRET'],
    timeoutSeconds: 120,
  },
  async () => {
    console.log('📬 Polling Gmail inbox...');
    
    try {
      const clientId = process.env.GMAIL_CLIENT_ID;
      const clientSecret = process.env.GMAIL_CLIENT_SECRET;
      
      // Check if Gmail is authorized
      const tokens = await getGmailTokens();
      if (!tokens) {
        console.log('⚠️ Gmail not authorized yet. Skipping poll.');
        return;
      }
      
      const gmail = await getGmailClient(clientId, clientSecret);
      
      // Get sync state
      const syncDoc = await db.collection('system').doc('gmail_sync').get();
      const syncData = syncDoc.exists ? syncDoc.data() : { lastCheckTimestamp: Date.now() - 86400000 }; // Default to 24h ago
      
      // Calculate time window (last check to now)
      const afterTimestamp = Math.floor(syncData.lastCheckTimestamp / 1000);
      const query = `after:${afterTimestamp} in:inbox`;
      
      console.log(`🔍 Searching for emails: ${query}`);
      
      // List messages
      const listResponse = await gmail.users.messages.list({
        userId: 'me',
        q: query,
        maxResults: 50,
      });
      
      const messages = listResponse.data.messages || [];
      console.log(`📧 Found ${messages.length} new messages`);
      
      let processedCount = 0;
      
      for (const msg of messages) {
        // Check if we already processed this message
        const existingMsg = await db.collection('messages')
          .where('channelMetadata.gmail.messageId', '==', msg.id)
          .limit(1)
          .get();
        
        if (!existingMsg.empty) {
          console.log(`⏭️ Skipping already processed message: ${msg.id}`);
          continue;
        }
        
        // Get full message details
        const fullMessage = await gmail.users.messages.get({
          userId: 'me',
          id: msg.id,
          format: 'full',
        });
        
        await processGmailMessageData(fullMessage.data);
        processedCount++;
      }
      
      // Update last check timestamp
      await db.collection('system').doc('gmail_sync').update({
        lastCheckTimestamp: Date.now(),
        lastPollAt: admin.firestore.FieldValue.serverTimestamp(),
        lastPollCount: messages.length,
        lastProcessedCount: processedCount,
      });
      
      console.log(`✅ Gmail poll complete. Processed ${processedCount} new messages.`);
    } catch (error) {
      console.error('❌ Gmail poll error:', error);
      
      // Log error but don't throw to prevent retries
      await db.collection('system').doc('gmail_sync').update({
        lastError: error.message,
        lastErrorAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }
);

/**
 * Process a Gmail message and create Firestore records
 */
async function processGmailMessageData(gmailMessage) {
  const headers = gmailMessage.payload.headers;
  
  const getHeader = (name) => {
    const header = headers.find(h => h.name.toLowerCase() === name.toLowerCase());
    return header ? header.value : null;
  };
  
  const from = getHeader('From');
  const to = getHeader('To');
  const subject = getHeader('Subject') || '(No Subject)';
  const messageId = gmailMessage.id;
  const threadId = gmailMessage.threadId;
  const internalDate = parseInt(gmailMessage.internalDate);
  
  // Extract email address from "Name <email@example.com>" format
  const emailMatch = from.match(/<([^>]+)>/);
  const fromEmail = emailMatch ? emailMatch[1] : from;
  const fromName = emailMatch ? from.replace(/<[^>]+>/, '').trim() : null;
  
  // Get message body
  let body = '';
  if (gmailMessage.payload.body && gmailMessage.payload.body.data) {
    body = Buffer.from(gmailMessage.payload.body.data, 'base64').toString('utf-8');
  } else if (gmailMessage.payload.parts) {
    // Find text/plain or text/html part
    const textPart = gmailMessage.payload.parts.find(p => p.mimeType === 'text/plain');
    const htmlPart = gmailMessage.payload.parts.find(p => p.mimeType === 'text/html');
    
    if (textPart && textPart.body && textPart.body.data) {
      body = Buffer.from(textPart.body.data, 'base64').toString('utf-8');
    } else if (htmlPart && htmlPart.body && htmlPart.body.data) {
      // Strip HTML tags for plain text
      const html = Buffer.from(htmlPart.body.data, 'base64').toString('utf-8');
      body = html.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim();
    }
  }
  
  // Truncate very long bodies
  if (body.length > 10000) {
    body = body.substring(0, 10000) + '... [truncated]';
  }
  
  console.log(`📨 Processing email from: ${fromEmail}, subject: ${subject}`);
  
  // Extract booking references
  const detectedBookingNumbers = extractBookingReferences(body + ' ' + subject);
  
  // Find or create customer
  const customerId = await findOrCreateCustomer('gmail', fromEmail, fromName);
  
  // Find or create conversation
  const conversationId = await findOrCreateConversation(
    customerId,
    'gmail',
    threadId,
    subject,
    body.substring(0, 200)
  );
  
  // Create message document
  const messageData = {
    conversationId,
    customerId,
    channel: 'gmail',
    direction: 'inbound',
    subject,
    content: body,
    timestamp: admin.firestore.Timestamp.fromMillis(internalDate),
    channelMetadata: {
      gmail: {
        messageId,
        threadId,
        from: fromEmail,
        fromName,
        to: to ? to.split(',').map(e => e.trim()) : [],
        labels: gmailMessage.labelIds || [],
      },
    },
    bookingIds: [],
    detectedBookingNumbers,
    status: 'pending',
    flaggedForReview: false,
    priority: detectedBookingNumbers.length > 0 ? 'normal' : 'low',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  
  const msgRef = await db.collection('messages').add(messageData);
  console.log(`✅ Created message: ${msgRef.id} for conversation: ${conversationId}`);
  
  // Update conversation
  await db.collection('conversations').doc(conversationId).update({
    messageIds: admin.firestore.FieldValue.arrayUnion(msgRef.id),
    lastMessageAt: admin.firestore.Timestamp.fromMillis(internalDate),
    lastMessagePreview: body.substring(0, 100),
    unreadCount: admin.firestore.FieldValue.increment(1),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  
  return msgRef.id;
}

/**
 * Send email via Gmail (called when staff replies)
 */
exports.sendGmailReply = onCall(
  {
    region: 'us-central1',
    secrets: ['GMAIL_CLIENT_ID', 'GMAIL_CLIENT_SECRET'],
  },
  async (request) => {
    const { conversationId, content, messageId } = request.data;
    
    if (!conversationId || !content) {
      throw new Error('Missing required fields: conversationId, content');
    }
    
    try {
      const clientId = process.env.GMAIL_CLIENT_ID;
      const clientSecret = process.env.GMAIL_CLIENT_SECRET;
      
      // Get conversation details
      const convDoc = await db.collection('conversations').doc(conversationId).get();
      if (!convDoc.exists) {
        throw new Error('Conversation not found');
      }
      const conv = convDoc.data();
      
      // Get customer email
      const customerDoc = await db.collection('customers').doc(conv.customerId).get();
      const customer = customerDoc.data();
      const toEmail = customer.channels?.gmail || customer.email;
      
      if (!toEmail) {
        throw new Error('Customer email not found');
      }
      
      const gmail = await getGmailClient(clientId, clientSecret);
      const tokens = await getGmailTokens();
      
      // Build email
      const subject = conv.subject.startsWith('Re:') ? conv.subject : `Re: ${conv.subject}`;
      const threadId = conv.channelMetadata?.gmail?.threadId;
      
      // Get original message ID for threading
      let inReplyTo = '';
      let references = '';
      if (messageId) {
        const origMsg = await db.collection('messages').doc(messageId).get();
        if (origMsg.exists) {
          const origData = origMsg.data();
          inReplyTo = origData.channelMetadata?.gmail?.messageId || '';
          references = inReplyTo;
        }
      }
      
      // Create RFC 2822 formatted email
      const emailLines = [
        `From: ${tokens.email}`,
        `To: ${toEmail}`,
        `Subject: ${subject}`,
        inReplyTo ? `In-Reply-To: <${inReplyTo}>` : '',
        references ? `References: <${references}>` : '',
        'Content-Type: text/plain; charset=utf-8',
        '',
        content,
      ].filter(Boolean);
      
      const rawMessage = Buffer.from(emailLines.join('\r\n'))
        .toString('base64')
        .replace(/\+/g, '-')
        .replace(/\//g, '_')
        .replace(/=+$/, '');
      
      // Send email
      const sendResponse = await gmail.users.messages.send({
        userId: 'me',
        requestBody: {
          raw: rawMessage,
          threadId: threadId,
        },
      });
      
      console.log(`📤 Email sent: ${sendResponse.data.id}`);
      
      // Create outbound message record
      const outboundMsg = {
        conversationId,
        customerId: conv.customerId,
        channel: 'gmail',
        direction: 'outbound',
        subject,
        content,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        channelMetadata: {
          gmail: {
            messageId: sendResponse.data.id,
            threadId: sendResponse.data.threadId,
            from: tokens.email,
            to: [toEmail],
          },
        },
        status: 'sent',
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        sentBy: request.auth?.uid || 'system',
      };
      
      const outMsgRef = await db.collection('messages').add(outboundMsg);
      
      // Update conversation
      await db.collection('conversations').doc(conversationId).update({
        messageIds: admin.firestore.FieldValue.arrayUnion(outMsgRef.id),
        lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
        lastMessagePreview: content.substring(0, 100),
        unreadCount: 0,
        status: 'active',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      return {
        success: true,
        messageId: outMsgRef.id,
        gmailMessageId: sendResponse.data.id,
      };
    } catch (error) {
      console.error('❌ Error sending Gmail reply:', error);
      throw new Error(`Failed to send email: ${error.message}`);
    }
  }
);

/**
 * Manual trigger to poll Gmail (for testing)
 */
exports.triggerGmailPoll = onRequest(
  {
    region: 'us-central1',
    secrets: ['GMAIL_CLIENT_ID', 'GMAIL_CLIENT_SECRET'],
    invoker: 'public',
  },
  async (req, res) => {
    console.log('📬 Manual Gmail poll triggered...');
    
    try {
      const clientId = process.env.GMAIL_CLIENT_ID;
      const clientSecret = process.env.GMAIL_CLIENT_SECRET;
      
      const tokens = await getGmailTokens();
      if (!tokens) {
        res.status(400).send('Gmail not authorized. Visit /gmailOAuthStart first.');
        return;
      }
      
      const gmail = await getGmailClient(clientId, clientSecret);
      
      // Get last 10 messages from inbox
      const listResponse = await gmail.users.messages.list({
        userId: 'me',
        q: 'in:inbox',
        maxResults: 10,
      });
      
      const messages = listResponse.data.messages || [];
      const results = [];
      
      for (const msg of messages) {
        const existingMsg = await db.collection('messages')
          .where('channelMetadata.gmail.messageId', '==', msg.id)
          .limit(1)
          .get();
        
        if (!existingMsg.empty) {
          results.push({ id: msg.id, status: 'skipped (already processed)' });
          continue;
        }
        
        const fullMessage = await gmail.users.messages.get({
          userId: 'me',
          id: msg.id,
          format: 'full',
        });
        
        const msgId = await processGmailMessageData(fullMessage.data);
        results.push({ id: msg.id, status: 'processed', firestoreId: msgId });
      }
      
      // Update sync timestamp
      await db.collection('system').doc('gmail_sync').update({
        lastCheckTimestamp: Date.now(),
        lastManualPollAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      res.json({
        success: true,
        email: tokens.email,
        messagesFound: messages.length,
        results,
      });
    } catch (error) {
      console.error('❌ Manual poll error:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * Check Gmail connection status
 */
exports.gmailStatus = onRequest(
  {
    region: 'us-central1',
    invoker: 'public',
  },
  async (req, res) => {
    try {
      const tokens = await getGmailTokens();
      const syncDoc = await db.collection('system').doc('gmail_sync').get();
      const syncData = syncDoc.exists ? syncDoc.data() : null;
      
      res.json({
        connected: !!tokens,
        email: tokens?.email || null,
        lastSync: syncData?.lastPollAt?.toDate() || null,
        lastPollCount: syncData?.lastPollCount || 0,
        lastError: syncData?.lastError || null,
        setupUrl: tokens ? null : 'https://us-central1-aurora-viking-staff.cloudfunctions.net/gmailOAuthStart',
      });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  }
);

