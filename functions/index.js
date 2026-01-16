const { onRequest } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall } = require('firebase-functions/v2/https');
const { onDocumentWritten, onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');
const { getFirestore } = require('firebase-admin/firestore');
const crypto = require('crypto');
const https = require('https');
const { google } = require('googleapis');

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
    await db.collection('tour_reports').doc(targetDate).set(reportData, { merge: true });
    console.log(`✅ Report saved to Firestore: tour_reports/${targetDate}`);
  } catch (error) {
    console.error('❌ Error saving to Firestore:', error);
    return { success: false, message: 'Error saving report: ' + error.message, date: targetDate };
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

      // Pagination: fetch all bookings in batches
      const pageSize = 50;
      let allBookings = [];
      let offset = 0;
      let totalHits = 0;
      let hasMore = true;

      while (hasMore) {
        // Prepare request body with pagination
        // Note: productConfirmationDateRange filters by the activity/tour date
        const requestBody = {
          productConfirmationDateRange: {
            from: startDate,
            to: endDate,
          },
          offset: offset,
          limit: pageSize,
        };

        // Make request to Bokun API
        const result = await new Promise((resolve, reject) => {
          const postData = JSON.stringify(requestBody);

          // Need fresh signature for each request
          const now = new Date();
          const bokunDate = now.toISOString().replace('T', ' ').substring(0, 19);
          const message = bokunDate + accessKey + method + path;
          const sig = crypto
            .createHmac('sha1', secretKey)
            .update(message)
            .digest('base64');

          const options = {
            hostname: 'api.bokun.io',
            path: '/booking.json/booking-search',
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Content-Length': Buffer.byteLength(postData),
              'X-Bokun-AccessKey': accessKey,
              'X-Bokun-Date': bokunDate,
              'X-Bokun-Signature': sig,
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

        // Accumulate results
        const items = result.items || [];
        allBookings = allBookings.concat(items);
        totalHits = result.totalHits || allBookings.length;

        console.log(`Fetched page ${Math.floor(offset / pageSize) + 1}: ${items.length} bookings (total so far: ${allBookings.length}/${totalHits})`);

        // Check if there are more pages
        offset += pageSize;
        hasMore = items.length === pageSize && allBookings.length < totalHits;

        // Safety limit to prevent infinite loops
        if (offset > 1000) {
          console.log('Safety limit reached (1000 bookings), stopping pagination');
          hasMore = false;
        }
      }

      console.log(`Successfully fetched ${allBookings.length} total bookings for user ${uid}`);

      // Return combined result
      res.status(200).json({
        result: {
          items: allBookings,
          totalHits: totalHits,
        }
      });

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

// ============================================
// MANUAL TRIGGER - For testing or regenerating reports
// ============================================
exports.generateTourReportManual = onCall(
  {
    region: 'us-central1',

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
      const icelandYesterday = new Date(yesterday.toLocaleString('en-US', { timeZone: 'Atlantic/Reykjavik' }));
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
        return { success: false, message: 'No admin users found' };
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
        return { success: false, message: 'No FCM tokens found for admins' };
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
      return { success: false, message: 'No FCM tokens found for admins' };
    }

    return await sendPushNotifications(tokens, title, body, data, adminNames);
  } catch (error) {
    console.error('❌ Error sending notification to admins:', error);
    return { success: false, error: error.message };
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
      return { success: false, message: 'No users found' };
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
      return { success: false, message: 'No FCM tokens found' };
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
    return { success: false, error: error.message };
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
 * @param {string} inboxEmail - The inbox that received this message (e.g., info@, photo@)
 */
async function findOrCreateConversation(customerId, channel, threadId, subject, messagePreview, inboxEmail = null) {
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
    inboxEmail: inboxEmail || null,  // Store which inbox this conversation belongs to
    subject: subject || null,
    bookingIds: [],
    messageIds: [],
    status: 'active',
    lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
    lastMessagePreview: messagePreview.substring(0, 100),
    unreadCount: 1,
    channelMetadata: channel === 'gmail' && threadId ? { gmail: { threadId, inbox: inboxEmail } } : {},
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  const docRef = await conversationsRef.add(newConversation);
  console.log(`💬 Created new conversation: ${docRef.id} (inbox: ${inboxEmail})`);
  return docRef.id;
}

/**
 * Process incoming Gmail message (triggered by Pub/Sub - placeholder)
 * In production, this would be connected to Gmail Push Notifications
 */
exports.processGmailMessage = onCall(
  {
    region: 'us-central1',

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
 * Store Gmail tokens in Firestore (supports multiple accounts)
 * Each account is stored in system/gmail_accounts/{emailId}
 */
async function storeGmailTokens(email, tokens) {
  // Use email as document ID (replace special chars)
  const emailId = email.replace(/[@.]/g, '_');

  await db.collection('system').doc('gmail_accounts').collection('accounts').doc(emailId).set({
    email,
    accessToken: tokens.access_token,
    refreshToken: tokens.refresh_token,
    expiryDate: tokens.expiry_date,
    lastCheckTimestamp: Date.now(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  console.log(`✅ Gmail tokens stored for ${email}`);
}

/**
 * Get Gmail tokens for a specific email from Firestore
 * Checks both new location (gmail_accounts) and old location (gmail_tokens) for backwards compatibility
 */
async function getGmailTokens(email) {
  const emailId = email.replace(/[@.]/g, '_');

  // Try new location first
  const newDoc = await db.collection('system').doc('gmail_accounts').collection('accounts').doc(emailId).get();
  if (newDoc.exists) {
    return { ...newDoc.data(), id: emailId };
  }

  // Fallback to old location (system/gmail_tokens)
  console.log(`📍 Checking legacy token location for ${email}`);
  const oldDoc = await db.collection('system').doc('gmail_tokens').get();
  if (oldDoc.exists) {
    const data = oldDoc.data();
    // Check if email matches
    if (data.email === email || email === 'info@auroraviking.is') {
      console.log(`✅ Found tokens in legacy location for ${email}`);
      return { ...data, id: emailId };
    }
  }

  return null;
}

/**
 * Get all connected Gmail accounts
 */
async function getAllGmailAccounts() {
  const snapshot = await db.collection('system').doc('gmail_accounts').collection('accounts').get();
  if (snapshot.empty) {
    return [];
  }
  return snapshot.docs.map(doc => ({ ...doc.data(), id: doc.id }));
}

/**
 * Update sync state for a specific Gmail account
 */
async function updateGmailSyncState(email, updates) {
  const emailId = email.replace(/[@.]/g, '_');
  await db.collection('system').doc('gmail_accounts').collection('accounts').doc(emailId).update({
    ...updates,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/**
 * Auto-migrate legacy Gmail account to new multi-account structure
 * Returns true if migration was successful
 */
async function autoMigrateLegacyGmailAccount() {
  try {
    // Check for old tokens in legacy location
    const oldTokensDoc = await db.collection('system').doc('gmail_tokens').get();
    if (!oldTokensDoc.exists) {
      console.log('No legacy gmail_tokens found');
      return false;
    }

    const oldTokens = oldTokensDoc.data();
    console.log(`📧 Found legacy account: ${oldTokens.email}`);

    // Get old sync state
    const oldSyncDoc = await db.collection('system').doc('gmail_sync').get();
    const oldSync = oldSyncDoc.exists ? oldSyncDoc.data() : {};

    // Create new document ID
    const emailId = oldTokens.email.replace(/[@.]/g, '_');

    // Check if already migrated
    const existingDoc = await db.collection('system').doc('gmail_accounts').collection('accounts').doc(emailId).get();
    if (existingDoc.exists) {
      console.log('Account already migrated');
      return true;
    }

    // Create new account document
    const newAccountData = {
      email: oldTokens.email,
      accessToken: oldTokens.accessToken,
      refreshToken: oldTokens.refreshToken,
      expiryDate: oldTokens.expiryDate,
      lastCheckTimestamp: oldSync.lastCheckTimestamp || Date.now(),
      lastPollAt: oldSync.lastPollAt || null,
      lastPollCount: oldSync.lastPollCount || 0,
      lastProcessedCount: oldSync.lastProcessedCount || 0,
      lastError: null,
      migratedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    // Save to new location
    await db.collection('system').doc('gmail_accounts').collection('accounts').doc(emailId).set(newAccountData);
    console.log(`✅ Auto-migrated ${oldTokens.email} to new structure`);

    return true;
  } catch (error) {
    console.error('❌ Auto-migration error:', error);
    return false;
  }
}

/**
 * Get authenticated Gmail client for a specific email account
 */
async function getGmailClient(email, clientId, clientSecret) {
  const tokens = await getGmailTokens(email);
  if (!tokens) {
    throw new Error(`Gmail account ${email} not authorized. Please complete OAuth flow first.`);
  }

  const oauth2Client = getGmailOAuth2Client(clientId, clientSecret);
  oauth2Client.setCredentials({
    access_token: tokens.accessToken,
    refresh_token: tokens.refreshToken,
    expiry_date: tokens.expiryDate,
  });

  // Handle token refresh
  oauth2Client.on('tokens', async (newTokens) => {
    console.log(`🔄 Gmail tokens refreshed for ${email}`);
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

      // Store tokens (this also initializes sync state)
      await storeGmailTokens(email, tokens);

      // Get count of connected accounts
      const accounts = await getAllGmailAccounts();

      res.send(`
        <html>
          <head>
            <title>Gmail Connected!</title>
            <style>
              body { font-family: Arial, sans-serif; max-width: 600px; margin: 50px auto; padding: 20px; text-align: center; }
              .success { color: #34a853; font-size: 48px; }
              .accounts { background: #f5f5f5; padding: 15px; border-radius: 8px; margin-top: 20px; }
            </style>
          </head>
          <body>
            <div class="success">✅</div>
            <h1>Gmail Connected Successfully!</h1>
            <p>Email: <strong>${email}</strong></p>
            <p>The Aurora Viking Staff app will now receive emails from this inbox.</p>
            <div class="accounts">
              <strong>Connected Accounts (${accounts.length}):</strong><br/>
              ${accounts.map(a => a.email).join('<br/>')}
            </div>
            <p style="margin-top: 20px;">You can close this window.</p>
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
    schedule: 'every 1 minutes',
    region: 'us-central1',
    secrets: ['GMAIL_CLIENT_ID', 'GMAIL_CLIENT_SECRET'],
    timeoutSeconds: 60,
  },
  async () => {
    console.log('📬 Polling all Gmail inboxes...');

    try {
      const clientId = process.env.GMAIL_CLIENT_ID;
      const clientSecret = process.env.GMAIL_CLIENT_SECRET;

      // Get all connected Gmail accounts
      let accounts = await getAllGmailAccounts();

      // Auto-migrate from old structure if needed
      if (accounts.length === 0) {
        console.log('🔄 No accounts in new structure, checking for legacy accounts...');
        const migrated = await autoMigrateLegacyGmailAccount();
        if (migrated) {
          accounts = await getAllGmailAccounts();
        }
      }

      if (accounts.length === 0) {
        console.log('⚠️ No Gmail accounts authorized yet. Skipping poll.');
        return;
      }

      console.log(`📫 Found ${accounts.length} connected Gmail account(s)`);

      let totalProcessed = 0;

      // Poll each account
      for (const account of accounts) {
        try {
          console.log(`\n📧 Polling: ${account.email}`);
          const processedCount = await pollSingleGmailAccount(account, clientId, clientSecret);
          totalProcessed += processedCount;
        } catch (accountError) {
          console.error(`❌ Error polling ${account.email}:`, accountError.message);
          // Update error state for this account
          await updateGmailSyncState(account.email, {
            lastError: accountError.message,
            lastErrorAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      }

      console.log(`\n✅ Gmail poll complete. Processed ${totalProcessed} new messages across ${accounts.length} account(s).`);
    } catch (error) {
      console.error('❌ Gmail poll error:', error);
    }
  }
);

/**
 * Poll a single Gmail account for new messages
 */
async function pollSingleGmailAccount(account, clientId, clientSecret) {
  const gmail = await getGmailClient(account.email, clientId, clientSecret);

  // Calculate time window (last check to now, default to 24h ago)
  const lastCheck = account.lastCheckTimestamp || (Date.now() - 86400000);
  const afterTimestamp = Math.floor(lastCheck / 1000);
  const query = `after:${afterTimestamp} in:inbox`;

  console.log(`🔍 Searching: ${query}`);

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
      console.log(`⏭️ Skipping already processed: ${msg.id}`);
      continue;
    }

    // Get full message details
    const fullMessage = await gmail.users.messages.get({
      userId: 'me',
      id: msg.id,
      format: 'full',
    });

    // Pass the inbox email so we know which account received this
    await processGmailMessageData(fullMessage.data, account.email);
    processedCount++;
  }

  // Update sync state for this account
  await updateGmailSyncState(account.email, {
    lastCheckTimestamp: Date.now(),
    lastPollAt: admin.firestore.FieldValue.serverTimestamp(),
    lastPollCount: messages.length,
    lastProcessedCount: processedCount,
    lastError: null,  // Clear any previous error
  });

  console.log(`✅ Processed ${processedCount} from ${account.email}`);
  return processedCount;
}

/**
 * Process a Gmail message and create Firestore records
 * @param {Object} gmailMessage - The Gmail message data
 * @param {string} inboxEmail - The inbox email that received this message (e.g., info@, photo@)
 */
async function processGmailMessageData(gmailMessage, inboxEmail = 'info@auroraviking.is') {
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

  // Get message body - extract BOTH plain text and HTML for rich display
  let bodyPlain = '';
  let bodyHtml = '';

  function extractBodiesFromPart(part, results = { plain: '', html: '' }) {
    if (!part) return results;

    // Direct body data
    if (part.body && part.body.data) {
      const decoded = Buffer.from(part.body.data, 'base64').toString('utf-8');
      if (part.mimeType === 'text/plain' && !results.plain) {
        results.plain = decoded;
      } else if (part.mimeType === 'text/html' && !results.html) {
        results.html = decoded;
      }
    }

    // Nested parts - recursively search
    if (part.parts) {
      for (const subPart of part.parts) {
        extractBodiesFromPart(subPart, results);
      }
    }

    return results;
  }

  const bodies = extractBodiesFromPart(gmailMessage.payload);
  bodyHtml = bodies.html || '';
  bodyPlain = bodies.plain || '';

  // If we only have HTML, create plain text version
  if (!bodyPlain && bodyHtml) {
    bodyPlain = bodyHtml
      .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '')
      .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '')
      .replace(/<[^>]*>/g, ' ')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/\s+/g, ' ')
      .trim();
  }

  // Use plain text as the main body (for previews and search)
  let body = bodyPlain || bodyHtml;

  console.log(`📝 Extracted body: plain=${bodyPlain.length} chars, html=${bodyHtml.length} chars`);

  // Truncate very long bodies
  if (body.length > 10000) {
    body = body.substring(0, 10000) + '... [truncated]';
  }
  if (bodyHtml.length > 50000) {
    bodyHtml = bodyHtml.substring(0, 50000) + '... [truncated]';
  }

  console.log(`📨 Processing email from: ${fromEmail}, subject: ${subject}`);

  // Extract booking references
  const detectedBookingNumbers = extractBookingReferences(body + ' ' + subject);

  // Find or create customer
  const customerId = await findOrCreateCustomer('gmail', fromEmail, fromName);

  // Find or create conversation (pass inbox email for filtering)
  const conversationId = await findOrCreateConversation(
    customerId,
    'gmail',
    threadId,
    subject,
    body.substring(0, 200),
    inboxEmail  // Which inbox received this message
  );

  // Create message document
  const messageData = {
    conversationId,
    customerId,
    channel: 'gmail',
    direction: 'inbound',
    subject,
    content: body,
    contentHtml: bodyHtml || null,  // Store HTML for rich display
    timestamp: admin.firestore.Timestamp.fromMillis(internalDate),
    channelMetadata: {
      gmail: {
        messageId,
        threadId,
        from: fromEmail,
        fromName,
        to: to ? to.split(',').map(e => e.trim()) : [],
        labels: gmailMessage.labelIds || [],
        inbox: inboxEmail,  // Which inbox received this (info@, photo@, etc.)
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

      // Determine which inbox to send from (use original inbox or default)
      const inboxEmail = conv.channelMetadata?.gmail?.inbox || 'info@auroraviking.is';
      console.log(`📤 Sending reply from: ${inboxEmail}`);

      const gmail = await getGmailClient(inboxEmail, clientId, clientSecret);
      const tokens = await getGmailTokens(inboxEmail);

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
 * Polls all connected accounts
 */
exports.triggerGmailPoll = onRequest(
  {
    region: 'us-central1',
    secrets: ['GMAIL_CLIENT_ID', 'GMAIL_CLIENT_SECRET'],

  },
  async (req, res) => {
    console.log('📬 Manual Gmail poll triggered...');

    try {
      const clientId = process.env.GMAIL_CLIENT_ID;
      const clientSecret = process.env.GMAIL_CLIENT_SECRET;

      const accounts = await getAllGmailAccounts();
      if (accounts.length === 0) {
        res.status(400).send('No Gmail accounts authorized. Visit /gmailOAuthStart first.');
        return;
      }

      const allResults = [];

      for (const account of accounts) {
        try {
          const gmail = await getGmailClient(account.email, clientId, clientSecret);

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

            const msgId = await processGmailMessageData(fullMessage.data, account.email);
            results.push({ id: msg.id, status: 'processed', firestoreId: msgId });
          }

          // Update sync timestamp for this account
          await updateGmailSyncState(account.email, {
            lastCheckTimestamp: Date.now(),
            lastManualPollAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          allResults.push({
            email: account.email,
            messagesFound: messages.length,
            results,
          });
        } catch (accountError) {
          allResults.push({
            email: account.email,
            error: accountError.message,
          });
        }
      }

      res.json({
        success: true,
        accountsPolled: accounts.length,
        results: allResults,
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

  },
  async (req, res) => {
    try {
      const accounts = await getAllGmailAccounts();

      res.json({
        connected: accounts.length > 0,
        accountCount: accounts.length,
        accounts: accounts.map(a => ({
          email: a.email,
          lastSync: a.lastPollAt?.toDate() || null,
          lastPollCount: a.lastPollCount || 0,
          lastError: a.lastError || null,
        })),
        addAccountUrl: 'https://us-central1-aurora-viking-staff.cloudfunctions.net/gmailOAuthStart',
      });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * Firestore trigger: Auto-send email when outbound message is created
 * This fires when staff replies from the app
 */
exports.onOutboundMessageCreated = onDocumentCreated(
  {
    document: 'messages/{messageId}',
    region: 'us-central1',
    secrets: ['GMAIL_CLIENT_ID', 'GMAIL_CLIENT_SECRET'],
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log('No data in message document');
      return;
    }

    const messageData = snapshot.data();
    const messageId = event.params.messageId;

    // Only process outbound messages that haven't been sent yet
    if (messageData.direction !== 'outbound') {
      return;
    }

    if (messageData.status === 'sent' || messageData.gmailMessageId) {
      console.log(`Message ${messageId} already sent, skipping`);
      return;
    }

    console.log(`📤 Sending outbound message: ${messageId}`);

    try {
      const clientId = process.env.GMAIL_CLIENT_ID;
      const clientSecret = process.env.GMAIL_CLIENT_SECRET;

      // Get conversation for subject and thread info
      const convDoc = await db.collection('conversations').doc(messageData.conversationId).get();
      if (!convDoc.exists) {
        console.error('Conversation not found:', messageData.conversationId);
        return;
      }
      const conv = convDoc.data();

      // Get customer email
      const customerDoc = await db.collection('customers').doc(messageData.customerId).get();
      if (!customerDoc.exists) {
        console.error('Customer not found:', messageData.customerId);
        return;
      }
      const customer = customerDoc.data();
      const toEmail = customer.channels?.gmail || customer.email;

      if (!toEmail) {
        console.error('No email address for customer');
        await snapshot.ref.update({ status: 'failed', error: 'No customer email' });
        return;
      }

      // Determine which inbox to send from
      const inboxEmail = conv.channelMetadata?.gmail?.inbox || 'info@auroraviking.is';
      console.log(`📧 Sending from inbox: ${inboxEmail}`);

      // Get Gmail client
      const tokens = await getGmailTokens(inboxEmail);
      if (!tokens) {
        console.error(`No tokens found for inbox: ${inboxEmail}`);
        await snapshot.ref.update({ status: 'failed', error: `No tokens for ${inboxEmail}` });
        return;
      }

      const gmail = await getGmailClient(inboxEmail, clientId, clientSecret);

      // Build email
      const subject = conv.subject?.startsWith('Re:') ? conv.subject : `Re: ${conv.subject || 'Your inquiry'}`;
      const threadId = conv.channelMetadata?.gmail?.threadId;

      // Create RFC 2822 formatted email
      const emailLines = [
        `From: Aurora Viking <${tokens.email}>`,
        `To: ${toEmail}`,
        `Subject: ${subject}`,
        'Content-Type: text/plain; charset=utf-8',
        '',
        messageData.content,
      ];

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
          threadId: threadId || undefined,
        },
      });

      console.log(`✅ Email sent via Gmail: ${sendResponse.data.id}`);

      // Update message with Gmail info
      await snapshot.ref.update({
        status: 'sent',
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        gmailMessageId: sendResponse.data.id,
        'channelMetadata.gmail.messageId': sendResponse.data.id,
        'channelMetadata.gmail.threadId': sendResponse.data.threadId,
      });

      console.log(`📧 Message ${messageId} sent successfully to ${toEmail}`);
    } catch (error) {
      console.error(`❌ Error sending message ${messageId}:`, error);

      // Mark as failed
      await snapshot.ref.update({
        status: 'failed',
        error: error.message,
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }
);

/**
 * One-time migration: Move existing Gmail account to new multi-account structure
 * Visit this URL once to migrate: /migrateGmailToMultiAccount
 */
exports.migrateGmailToMultiAccount = onRequest(
  {
    region: 'us-central1',
  },
  async (req, res) => {
    console.log('🔄 Migrating Gmail account to new structure...');

    try {
      // Get old tokens from the legacy location
      const oldTokensDoc = await db.collection('system').doc('gmail_tokens').get();
      if (!oldTokensDoc.exists) {
        res.send('No old gmail_tokens document found. Nothing to migrate.');
        return;
      }
      const oldTokens = oldTokensDoc.data();
      console.log(`📧 Found account: ${oldTokens.email}`);

      // Get old sync state
      const oldSyncDoc = await db.collection('system').doc('gmail_sync').get();
      const oldSync = oldSyncDoc.exists ? oldSyncDoc.data() : {};

      // Create new document ID
      const emailId = oldTokens.email.replace(/[@.]/g, '_');

      // Check if already migrated
      const existingDoc = await db.collection('system').doc('gmail_accounts').collection('accounts').doc(emailId).get();
      if (existingDoc.exists) {
        res.send(`Account ${oldTokens.email} already migrated.`);
        return;
      }

      // Create new account document
      const newAccountData = {
        email: oldTokens.email,
        accessToken: oldTokens.accessToken,
        refreshToken: oldTokens.refreshToken,
        expiryDate: oldTokens.expiryDate,
        lastCheckTimestamp: oldSync.lastCheckTimestamp || Date.now(),
        lastPollAt: oldSync.lastPollAt || null,
        lastPollCount: oldSync.lastPollCount || 0,
        lastProcessedCount: oldSync.lastProcessedCount || 0,
        lastError: null,
        migratedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      // Save to new location
      await db.collection('system').doc('gmail_accounts').collection('accounts').doc(emailId).set(newAccountData);

      res.send(`
        <html>
          <head><title>Migration Complete</title></head>
          <body style="font-family: Arial; max-width: 600px; margin: 50px auto; text-align: center;">
            <h1>✅ Migration Complete!</h1>
            <p>Account <strong>${oldTokens.email}</strong> migrated to new structure.</p>
            <p>New path: <code>system/gmail_accounts/accounts/${emailId}</code></p>
            <hr/>
            <p style="color: #666;">You can now add more accounts by visiting <a href="/gmailOAuthStart">/gmailOAuthStart</a></p>
          </body>
        </html>
      `);

    } catch (error) {
      console.error('❌ Migration error:', error);
      res.status(500).send(`Migration error: ${error.message}`);
    }
  }
);

// ============================================
// WEBSITE CHAT WIDGET FUNCTIONS
// ============================================

/**
 * Verify Firebase Auth token from request
 * Returns the decoded token with uid, or null if invalid
 * Skips verification for OPTIONS requests (CORS preflight)
 */
async function verifyWebsiteAuth(req) {
  // Skip auth for preflight requests
  if (req.method === 'OPTIONS') {
    return { uid: 'preflight', isOptions: true };
  }

  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return null;
  }

  try {
    const token = authHeader.split('Bearer ')[1];
    const decodedToken = await admin.auth().verifyIdToken(token);
    return decodedToken;
  } catch (error) {
    console.error('❌ Auth verification failed:', error.message);
    return null;
  }
}

/**
 * Create a new anonymous website chat session
 * Called when visitor opens chat widget for the first time
 * Requires Firebase Anonymous Auth token
 */
exports.createWebsiteSession = onRequest(
  {
    region: 'us-central1',
    cors: true,

  },
  async (req, res) => {
    console.log('🌐 Creating website chat session...');

    // Verify auth token
    const authUser = await verifyWebsiteAuth(req);
    if (!authUser) {
      console.log('❌ Unauthorized request to createWebsiteSession');
      return res.status(401).json({ error: 'Unauthorized - valid Firebase Auth token required' });
    }
    console.log('✅ Auth verified for uid:', authUser.uid);

    try {
      const { pageUrl, referrer, userAgent } = req.body;

      // Generate unique session ID
      const sessionId = 'ws_' + crypto.randomBytes(12).toString('hex');

      // Create anonymous customer
      const customerId = 'cust_website_' + crypto.randomBytes(8).toString('hex');
      const customerRef = await db.collection('customers').add({
        id: customerId,
        name: 'Website Visitor',
        email: null,
        phone: null,
        source: 'website_chat',
        sessionId: sessionId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        firstPageUrl: pageUrl || null,
        referrer: referrer || null,
        userAgent: userAgent || null,
      });

      // Create conversation
      const conversationRef = await db.collection('conversations').add({
        customerId: customerRef.id,
        customerName: 'Website Visitor',
        channel: 'website',
        subject: 'Website Chat',
        status: 'active',  // Must match Flutter ConversationStatus enum
        hasUnread: false,
        lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
        lastMessagePreview: '',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        channelMetadata: {
          website: {
            sessionId: sessionId,
            firstPageUrl: pageUrl || null,
            referrer: referrer || null,
          }
        },
        inboxEmail: 'website',
      });

      // Create website session document
      await db.collection('website_sessions').doc(sessionId).set({
        sessionId: sessionId,
        conversationId: conversationRef.id,
        customerId: customerRef.id,
        visitorName: null,
        visitorEmail: null,
        bookingRef: null,
        firstPageUrl: pageUrl || null,
        currentPageUrl: pageUrl || null,
        referrer: referrer || null,
        userAgent: userAgent || null,
        isOnline: true,
        lastSeen: admin.firestore.FieldValue.serverTimestamp(),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`✅ Website session created: ${sessionId}, conversation: ${conversationRef.id}`);

      res.json({
        sessionId,
        conversationId: conversationRef.id,
        customerId: customerRef.id,
      });

    } catch (error) {
      console.error('❌ Error creating website session:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * Update website session (page tracking, visitor identification)
 * Requires Firebase Anonymous Auth token
 */
exports.updateWebsiteSession = onRequest(
  {
    region: 'us-central1',
    cors: true,  // Allow ALL origins
  },
  async (req, res) => {
    // Verify auth token
    const authUser = await verifyWebsiteAuth(req);
    if (!authUser) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    try {
      const { sessionId, currentPageUrl, visitorName, visitorEmail, bookingRef } = req.body;

      if (!sessionId) {
        return res.status(400).json({ error: 'sessionId required' });
      }

      const sessionRef = db.collection('website_sessions').doc(sessionId);
      const session = await sessionRef.get();

      if (!session.exists) {
        return res.status(404).json({ error: 'Session not found' });
      }

      const updates = {
        lastSeen: admin.firestore.FieldValue.serverTimestamp(),
        isOnline: true,
      };

      if (currentPageUrl) updates.currentPageUrl = currentPageUrl;
      if (visitorName) updates.visitorName = visitorName;
      if (visitorEmail) updates.visitorEmail = visitorEmail;
      if (bookingRef) updates.bookingRef = bookingRef;

      await sessionRef.update(updates);

      // Also update customer record if we have new info
      const sessionData = session.data();
      if ((visitorName || visitorEmail) && sessionData.customerId) {
        const customerUpdates = {};
        if (visitorName) customerUpdates.name = visitorName;
        if (visitorEmail) customerUpdates.email = visitorEmail;

        await db.collection('customers').doc(sessionData.customerId).update(customerUpdates);

        // Update conversation with customer name
        if (visitorName) {
          await db.collection('conversations').doc(sessionData.conversationId).update({
            customerName: visitorName,
          });
        }
      }

      res.json({ success: true });

    } catch (error) {
      console.error('❌ Error updating session:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * Send a message from the website chat widget
 * Requires Firebase Anonymous Auth token
 */
exports.sendWebsiteMessage = onRequest(
  {
    region: 'us-central1',
    cors: true,  // Allow ALL origins
  },
  async (req, res) => {
    console.log('💬 Receiving website chat message...');

    // Verify auth token
    const authUser = await verifyWebsiteAuth(req);
    if (!authUser) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    try {
      const { sessionId, conversationId, content, visitorName, visitorEmail } = req.body;

      if (!content || !content.trim()) {
        return res.status(400).json({ error: 'Message content required' });
      }

      if (!sessionId || !conversationId) {
        return res.status(400).json({ error: 'sessionId and conversationId required' });
      }

      // Get session
      const sessionRef = db.collection('website_sessions').doc(sessionId);
      const session = await sessionRef.get();

      if (!session.exists) {
        return res.status(404).json({ error: 'Session not found' });
      }

      const sessionData = session.data();

      // Update visitor info if provided
      if (visitorName || visitorEmail) {
        const sessionUpdates = {};
        if (visitorName) sessionUpdates.visitorName = visitorName;
        if (visitorEmail) sessionUpdates.visitorEmail = visitorEmail;
        await sessionRef.update(sessionUpdates);

        // Update customer
        const customerUpdates = {};
        if (visitorName) customerUpdates.name = visitorName;
        if (visitorEmail) customerUpdates.email = visitorEmail;
        await db.collection('customers').doc(sessionData.customerId).update(customerUpdates);
      }

      // Create message
      const messageRef = await db.collection('messages').add({
        conversationId: conversationId,
        customerId: sessionData.customerId,
        channel: 'website',
        direction: 'inbound',
        content: content.trim(),
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        status: 'delivered',
        channelMetadata: {
          website: {
            sessionId: sessionId,
            pageUrl: sessionData.currentPageUrl,
          }
        },
      });

      // Update conversation
      await db.collection('conversations').doc(conversationId).update({
        lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
        lastMessagePreview: content.substring(0, 100),
        hasUnread: true,
        status: 'active',  // Must match Flutter ConversationStatus enum
        customerName: visitorName || sessionData.visitorName || 'Website Visitor',
      });

      // Update session last seen
      await sessionRef.update({
        lastSeen: admin.firestore.FieldValue.serverTimestamp(),
        isOnline: true,
      });

      console.log(`✅ Website message saved: ${messageRef.id}`);

      res.json({
        success: true,
        messageId: messageRef.id,
      });

    } catch (error) {
      console.error('❌ Error sending website message:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * Mark session as offline (heartbeat timeout)
 * Can be triggered by scheduler or when visitor closes tab
 * Requires Firebase Anonymous Auth token
 */
exports.updateWebsitePresence = onRequest(
  {
    region: 'us-central1',
    cors: true,  // Allow ALL origins
  },
  async (req, res) => {
    // Verify auth token
    const authUser = await verifyWebsiteAuth(req);
    if (!authUser) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    try {
      const { sessionId, isOnline } = req.body;

      if (!sessionId) {
        return res.status(400).json({ error: 'sessionId required' });
      }

      await db.collection('website_sessions').doc(sessionId).update({
        isOnline: isOnline !== false,
        lastSeen: admin.firestore.FieldValue.serverTimestamp(),
      });

      res.json({ success: true });

    } catch (error) {
      console.error('❌ Error updating presence:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * Send a reply from staff to website chat visitor
 * Called from the Flutter app when staff replies to a website conversation
 */
exports.sendWebsiteChatReply = onDocumentCreated(
  {
    document: 'messages/{messageId}',
    region: 'us-central1',
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const messageData = snapshot.data();
    const messageId = event.params.messageId;

    // Only process outbound website messages
    if (messageData.direction !== 'outbound' || messageData.channel !== 'website') {
      return;
    }

    console.log(`📤 Processing website reply: ${messageId}`);

    try {
      // Get conversation to find session
      const convDoc = await db.collection('conversations').doc(messageData.conversationId).get();
      if (!convDoc.exists) {
        console.log(`⚠️ Conversation ${messageData.conversationId} not found`);
        return;
      }

      const conv = convDoc.data();
      const sessionId = conv.channelMetadata?.website?.sessionId;

      if (!sessionId) {
        console.log('⚠️ No sessionId found for website conversation');
        return;
      }

      // Update message status to sent (visitor will poll for new messages)
      await snapshot.ref.update({
        status: 'sent',
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Update conversation
      await db.collection('conversations').doc(messageData.conversationId).update({
        lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
        lastMessagePreview: messageData.content.substring(0, 100),
        hasUnread: false,
        respondedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`✅ Website reply sent: ${messageId}`);

    } catch (error) {
      console.error(`❌ Error processing website reply:`, error);
    }
  }
);

// ============================================
// WEBSITE CHAT - Notification for new messages (to admins only)
// ============================================
exports.onWebsiteChatMessage = onDocumentCreated(
  {
    document: 'messages/{messageId}',
    region: 'us-central1',
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log('No data in snapshot');
      return null;
    }

    const messageData = snapshot.data();
    const messageId = event.params.messageId;

    // Only send notification for INBOUND website chat messages
    if (messageData.channel !== 'website' || messageData.direction !== 'inbound') {
      console.log(`ℹ️ Skipping notification - not an inbound website message`);
      return null;
    }

    console.log(`💬 New website chat message received: ${messageId}`);

    try {
      // Get conversation for more context
      const conversationDoc = await db.collection('conversations').doc(messageData.conversationId).get();
      const conversationData = conversationDoc.exists ? conversationDoc.data() : {};

      // Get visitor name if available
      const visitorName = conversationData.customerName && conversationData.customerName !== 'Website Visitor'
        ? conversationData.customerName
        : 'Website Visitor';

      // Get booking ref if available
      const bookingRef = conversationData.bookingIds && conversationData.bookingIds.length > 0
        ? ` (${conversationData.bookingIds[0]})`
        : '';

      // Truncate message for notification
      const messagePreview = messageData.content.length > 100
        ? messageData.content.substring(0, 100) + '...'
        : messageData.content;

      // Send notification to admins only
      await sendNotificationToAdminsOnly(
        `💬 Website Chat${bookingRef}`,
        `${visitorName}: ${messagePreview}`,
        {
          type: 'website_chat',
          conversationId: messageData.conversationId,
          messageId: messageId,
          visitorName: visitorName,
        }
      );

      console.log(`✅ Website chat notification sent to admins`);
      return { success: true };

    } catch (error) {
      console.error(`❌ Error sending website chat notification:`, error);
      return { success: false, error: error.message };
    }
  }
);

// ============================================
// PHASE 2: AI DRAFT RESPONSES
// ============================================

const Anthropic = require('@anthropic-ai/sdk');

/**
 * Generate AI draft response when new inbound message is created
 * DEPRECATED: Now using on-demand generateBookingAiAssist instead to save tokens
 * This function is disabled but kept for reference
 */
exports.generateAiDraft = onDocumentCreated(
  {
    document: 'messages/{messageId}',
    region: 'us-central1',
    secrets: ['ANTHROPIC_API_KEY'],
  },
  async (event) => {
    // DISABLED: Auto AI draft generation is disabled to save on API tokens
    // Use the on-demand generateBookingAiAssist function instead
    console.log('⏭️ Auto AI draft generation is DISABLED - use AI Assist button instead');
    return null;

    // Original code below (kept for reference)
    const snapshot = event.data;
    if (!snapshot) {
      console.log('No data in snapshot');
      return null;
    }

    const messageData = snapshot.data();
    const messageId = event.params.messageId;

    // Only generate drafts for inbound messages
    if (messageData.direction !== 'inbound') {
      console.log('⏭️ Skipping AI draft - not inbound message');
      return null;
    }

    console.log('🧠 Generating AI draft for message:', messageId);

    try {
      // Get conversation history
      const conversationId = messageData.conversationId;
      const messagesSnapshot = await db.collection('messages')
        .where('conversationId', '==', conversationId)
        .orderBy('timestamp', 'asc')
        .limit(10) // Last 10 messages for context
        .get();

      const conversationHistory = messagesSnapshot.docs.map(doc => ({
        direction: doc.data().direction,
        content: doc.data().content,
        subject: doc.data().subject,
      }));

      // Get customer info
      const customerDoc = await db.collection('customers').doc(messageData.customerId).get();
      const customer = customerDoc.exists ? customerDoc.data() : {};

      // Look up booking if detected
      const bookingContext = await getBookingContextForAi(messageData.detectedBookingNumbers);

      // Generate draft with Claude
      const draft = await generateDraftWithClaude({
        message: messageData,
        customer,
        bookingContext,
        conversationHistory,
      });

      // Save draft to message
      await db.collection('messages').doc(messageId).update({
        aiDraft: {
          content: draft.content,
          confidence: draft.confidence,
          suggestedTone: draft.tone,
          generatedAt: admin.firestore.FieldValue.serverTimestamp(),
          reasoning: draft.reasoning,
        },
        status: 'draftReady',
      });

      console.log('✅ AI draft saved for message:', messageId);
      return { success: true };
    } catch (error) {
      console.error('❌ Error generating AI draft:', error);
      // Don't fail the whole thing - just log and continue
      return { success: false, error: error.message };
    }
  }
);

// Helper: Get booking context for AI prompt
async function getBookingContextForAi(bookingNumbers) {
  if (!bookingNumbers || bookingNumbers.length === 0) {
    return 'No booking numbers detected in the message.';
  }

  // For now, just return the detected booking numbers
  // TODO: Later, query Bokun API for full booking details
  return `Customer mentioned booking(s): ${bookingNumbers.join(', ')}`;
}

// Helper: Generate draft with Claude
async function generateDraftWithClaude({ message, customer, bookingContext, conversationHistory }) {
  const anthropic = new Anthropic({
    apiKey: process.env.ANTHROPIC_API_KEY,
  });

  const systemPrompt = `You are a helpful customer service agent for Aurora Viking, 
a Northern Lights and aurora borealis tour company based in Reykjavik, Iceland.

COMPANY INFO:
- We run Northern Lights tours every night (weather permitting)
- Tours depart from Reykjavik, pickup from hotels/bus stops
- Standard tour is 4-5 hours
- Booking reference format: AV-XXXXX

NORTHERN LIGHTS POLICY (VERY IMPORTANT):
- If tour operates and NO Northern Lights are seen with naked eye: guests get UNLIMITED FREE RETRIES for 2 years
- NO REFUNDS if no lights are seen - only free retry option
- A faint naked-eye arc counts as a sighting
- Aurora visible only through camera does NOT count as sighting
- Guests MUST attend their original booked tour to qualify for retry
- No-shows, cancellations, or late arrivals forfeit the retry
- Free retry bookings must be made BEFORE 12:00 noon on the day of tour
- Retry seats are subject to availability

CANCELLATION & RESCHEDULING POLICY:
- Rescheduling within 24 hours of departure = treated as cancellation = NON-REFUNDABLE
- Once we grant a courtesy reschedule, it becomes FINAL (non-refundable, no further changes)
- If AURORA VIKING cancels the tour (weather, safety): guests may choose free rebooking OR full refund

IMPORTANT - WHAT TO NEVER SAY:
- NEVER offer percentage refunds (we don't do 50% refunds, etc.)
- NEVER promise refunds for no Northern Lights
- NEVER guarantee seats for retry on specific nights
- For complex refund/cancellation requests, say you'll escalate to the team

CUSTOMER CONTEXT:
- Name: ${customer.name || 'Unknown'}
- Email: ${customer.email || message.channelMetadata?.gmail?.from || 'Unknown'}
- Past interactions: ${customer.pastInteractions || 0}
- VIP: ${customer.vipStatus ? 'Yes' : 'No'}

BOOKING CONTEXT:
${bookingContext}

TONE GUIDELINES:
- Be warm, friendly, and professional
- Use the customer's name if known
- Be helpful and solution-oriented
- For weather questions, be optimistic but honest
- For reschedule requests within terms, be accommodating
- For requests outside policy, be empathetic but explain the terms clearly
- Keep responses concise (2-3 short paragraphs max)
- Include relevant emojis sparingly (🌌 ❄️ 📸)

Generate a helpful, professional response to the customer's inquiry.
Output ONLY the response text, no labels or prefixes.`;

  // Build message history
  const messages = conversationHistory.map(msg => ({
    role: msg.direction === 'inbound' ? 'user' : 'assistant',
    content: msg.subject ? `Subject: ${msg.subject}\n\n${msg.content}` : msg.content,
  }));

  // Ensure the last message is the current one
  if (messages.length === 0 || messages[messages.length - 1].content !== message.content) {
    const currentContent = message.subject
      ? `Subject: ${message.subject}\n\n${message.content}`
      : message.content;
    messages.push({
      role: 'user',
      content: currentContent,
    });
  }

  const response = await anthropic.messages.create({
    model: 'claude-sonnet-4-20250514',
    max_tokens: 1024,
    system: systemPrompt,
    messages: messages,
  });

  const draftContent = response.content[0].text;

  // Classify confidence based on message type
  let confidence = 0.85;
  const contentLower = message.content.toLowerCase();

  if (contentLower.includes('cancel') || contentLower.includes('refund')) {
    confidence = 0.6; // Lower confidence for sensitive topics
  } else if (contentLower.includes('weather') || contentLower.includes('aurora')) {
    confidence = 0.9; // High confidence for common questions
  } else if (contentLower.includes('pickup') || contentLower.includes('hotel')) {
    confidence = 0.88;
  } else if (contentLower.includes('photo') || contentLower.includes('picture')) {
    confidence = 0.92; // Very common request
  }

  return {
    content: draftContent,
    confidence,
    tone: 'friendly',
    reasoning: 'Generated based on conversation context and company guidelines',
  };
}

// ============================================
// BOOKING MANAGEMENT FUNCTIONS
// ============================================

/**
 * Get booking details by ID from Bokun
 */
exports.getBookingDetails = onRequest(
  {
    cors: true,
    secrets: ['BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY'],

  },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }

    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      res.status(401).json({ error: 'Unauthorized - missing token' });
      return;
    }

    try {
      const token = authHeader.split('Bearer ')[1];
      await admin.auth().verifyIdToken(token);

      const requestData = req.body.data || req.body;
      const { bookingId } = requestData;

      if (!bookingId) {
        res.status(400).json({ error: 'bookingId is required' });
        return;
      }

      const accessKey = process.env.BOKUN_ACCESS_KEY;
      const secretKey = process.env.BOKUN_SECRET_KEY;

      if (!accessKey || !secretKey) {
        res.status(500).json({ error: 'Bokun API keys not configured' });
        return;
      }

      const result = await makeBokunRequest(
        'GET',
        `/booking.json/${bookingId}`,
        null,
        accessKey,
        secretKey
      );

      res.status(200).json({ result });
    } catch (error) {
      console.error('Error in getBookingDetails:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * Reschedule a booking to a new date
 * Note: Bokun may handle this as cancel + rebook internally
 * Using onCall instead of onRequest to bypass Cloud Run IAM issues
 */
exports.rescheduleBooking = onCall(
  {
    region: 'us-central1',
    secrets: ['BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY'],
  },
  async (request) => {
    // Verify user is authenticated
    if (!request.auth) {
      throw new Error('Unauthorized - must be logged in');
    }
    const uid = request.auth.uid;

    const { bookingId, confirmationCode, newDate, reason } = request.data;

    if (!bookingId || !newDate) {
      throw new Error('bookingId and newDate are required');
    }

    const accessKey = process.env.BOKUN_ACCESS_KEY;
    const secretKey = process.env.BOKUN_SECRET_KEY;

    if (!accessKey || !secretKey) {
      throw new Error('Bokun API keys not configured');
    }

    // First, get the current booking details
    const currentBooking = await makeBokunRequest(
      'GET',
      `/booking.json/${bookingId}`,
      null,
      accessKey,
      secretKey
    );

    // Try to amend the booking with new date
    // Note: Bokun's amend API structure may vary - this is a best-effort implementation
    const amendRequest = {
      bookingId: bookingId,
      newStartDate: newDate,
      // Additional fields may be required depending on Bokun's API
    };

    try {
      const result = await makeBokunRequest(
        'POST',
        `/booking.json/${bookingId}/reschedule`,
        amendRequest,
        accessKey,
        secretKey
      );

      // Log the action to Firestore
      await admin.firestore().collection('booking_actions').add({
        bookingId,
        confirmationCode: confirmationCode || '',
        action: 'reschedule',
        performedBy: uid,
        performedAt: admin.firestore.FieldValue.serverTimestamp(),
        reason: reason || 'Rescheduled via admin app',
        originalData: {
          date: currentBooking.startDate || 'unknown',
        },
        newData: {
          date: newDate,
        },
        success: true,
        source: 'cloud_function',
      });

      return { result, success: true };
    } catch (amendError) {
      // If amend fails, log the error
      console.error('Bokun amend failed:', amendError.message);

      // Log failed attempt
      await admin.firestore().collection('booking_actions').add({
        bookingId,
        confirmationCode: confirmationCode || '',
        action: 'reschedule',
        performedBy: uid,
        performedAt: admin.firestore.FieldValue.serverTimestamp(),
        reason: reason || 'Attempted reschedule',
        newData: { date: newDate },
        success: false,
        errorMessage: amendError.message,
        source: 'cloud_function',
      });

      // Return error with suggestion
      throw new Error(`Reschedule failed: ${amendError.message}. You may need to cancel and rebook manually.`);
    }
  }
);

/**
 * Firestore Trigger: Process reschedule requests
 * Flutter writes to reschedule_requests collection, this trigger processes it
 * This bypasses Cloud Run IAM issues since Firestore triggers don't need external invocation
 */
exports.onRescheduleRequest = onDocumentCreated(
  {
    document: 'reschedule_requests/{requestId}',
    region: 'us-central1',
    secrets: ['BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY', 'BOKUN_OCTO_TOKEN'],
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log('No data in reschedule request');
      return;
    }

    const requestData = snapshot.data();
    const requestId = event.params.requestId;

    // Skip if already processed
    if (requestData.status === 'completed' || requestData.status === 'failed') {
      console.log(`Request ${requestId} already processed`);
      return;
    }

    const { bookingId, confirmationCode, newDate, reason, userId } = requestData;

    console.log(`📅 Processing reschedule request: ${requestId} for booking ${bookingId}`);

    // Mark as processing
    await snapshot.ref.update({ status: 'processing' });

    try {
      const accessKey = process.env.BOKUN_ACCESS_KEY;
      const secretKey = process.env.BOKUN_SECRET_KEY;
      const octoToken = process.env.BOKUN_OCTO_TOKEN;

      if (!accessKey || !secretKey) {
        throw new Error('Bokun API keys not configured');
      }
      if (!octoToken) {
        throw new Error('OCTO token not configured - required for programmatic reschedule');
      }

      // Use booking-search to find the booking and get product details
      console.log(`🔍 Searching for booking ${bookingId}...`);

      const now = new Date();
      const bokunDate = now.toISOString().replace('T', ' ').substring(0, 19);
      const searchPath = '/booking.json/booking-search';

      const message = bokunDate + accessKey + 'POST' + searchPath;
      const signature = crypto
        .createHmac('sha1', secretKey)
        .update(message)
        .digest('base64');

      const searchRequest = {
        id: parseInt(bookingId),
        limit: 10,
      };

      const searchResult = await new Promise((resolve, reject) => {
        const postData = JSON.stringify(searchRequest);

        const options = {
          hostname: 'api.bokun.io',
          path: searchPath,
          method: 'POST',
          headers: {
            'Content-Type': 'application/json;charset=UTF-8',
            'Content-Length': Buffer.byteLength(postData),
            'X-Bokun-AccessKey': accessKey,
            'X-Bokun-Date': bokunDate,
            'X-Bokun-Signature': signature,
          },
        };

        const apiReq = https.request(options, (apiRes) => {
          let data = '';
          apiRes.on('data', (chunk) => { data += chunk; });
          apiRes.on('end', () => {
            if (apiRes.statusCode >= 200 && apiRes.statusCode < 300) {
              try {
                resolve(JSON.parse(data));
              } catch (e) {
                reject(new Error('Failed to parse search response'));
              }
            } else {
              reject(new Error(`Bokun search error: ${apiRes.statusCode}`));
            }
          });
        });

        apiReq.on('error', (error) => reject(error));
        apiReq.write(postData);
        apiReq.end();
      });

      const foundBooking = searchResult.items?.find(b => String(b.id) === String(bookingId));
      if (!foundBooking) {
        throw new Error(`Booking ${bookingId} not found`);
      }

      console.log(`✅ Found booking ${bookingId} (${foundBooking.confirmationCode})`);

      const productBooking = foundBooking.productBookings?.[0];
      if (!productBooking) {
        throw new Error('No product booking found');
      }

      // Log productBooking structure to find optionId
      console.log(`📋 ProductBooking keys: ${Object.keys(productBooking).join(', ')}`);
      console.log(`📋 Product: ${JSON.stringify(productBooking.product || {})}`);

      const productId = productBooking.product?.id;
      // Option ID can be the activity ID, rate ID, or specific option
      // In Bokun, the optionId typically matches the product ID for simple products
      const optionId = productBooking.activity?.id || productBooking.rate?.id || productId;
      const currentDate = productBooking.startDate || 'Unknown';
      const customerName = foundBooking.customer?.firstName
        ? `${foundBooking.customer.firstName} ${foundBooking.customer.lastName || ''}`.trim()
        : 'Unknown Customer';

      console.log(`📦 Product ID: ${productId}, Option ID: ${optionId}, Current date: ${currentDate}, New date: ${newDate}`);

      // Helper function for OCTO API calls
      const octoRequest = (method, path, body = null) => {
        return new Promise((resolve, reject) => {
          const postData = body ? JSON.stringify(body) : null;

          const options = {
            hostname: 'api.bokun.io',
            path: `/octo/v1${path}`,
            method: method,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${octoToken}`,
            },
          };

          if (postData) {
            options.headers['Content-Length'] = Buffer.byteLength(postData);
          }

          console.log(`📡 OCTO ${method} ${options.path}`);

          const apiReq = https.request(options, (apiRes) => {
            let data = '';
            apiRes.on('data', (chunk) => { data += chunk; });
            apiRes.on('end', () => {
              console.log(`📡 OCTO Response: ${apiRes.statusCode}`);
              if (data.length > 0 && data.length < 1000) {
                console.log(`📡 OCTO Body: ${data}`);
              }

              if (apiRes.statusCode >= 200 && apiRes.statusCode < 300) {
                try {
                  resolve(data ? JSON.parse(data) : {});
                } catch (e) {
                  resolve(data);
                }
              } else {
                reject(new Error(`OCTO API error: ${apiRes.statusCode} - ${data}`));
              }
            });
          });

          apiReq.on('error', (error) => reject(error));
          if (postData) {
            apiReq.write(postData);
          }
          apiReq.end();
        });
      };

      // Step 0: Get list of products from OCTO to find correct IDs
      console.log(`🔍 Fetching OCTO products to find correct product/option IDs...`);
      let octoProductId = String(productId);  // Default to Bokun ID
      let octoOptionId = String(optionId);    // Default to Bokun optionId
      let octoUnitIds = [];  // Available unit IDs for this option
      let defaultUnitId = null;  // Default unit ID to use

      try {
        const octoProducts = await octoRequest('GET', '/products');
        console.log(`📦 OCTO returned ${Array.isArray(octoProducts) ? octoProducts.length : 0} products`);

        if (Array.isArray(octoProducts) && octoProducts.length > 0) {
          // Log first product for debugging
          const firstProduct = octoProducts[0];
          console.log(`📦 Sample OCTO product: id=${firstProduct.id}, internalName=${firstProduct.internalName}`);
          console.log(`📦 Sample options: ${JSON.stringify(firstProduct.options?.slice(0, 2) || [])}`);

          // Try to find matching product by Bokun product ID (OCTO stores Bokun ID as their ID)
          const matchingProduct = octoProducts.find(p =>
            String(p.id) === String(productId) ||
            p.internalName?.includes(String(productId))
          );

          let optionToUse = null;
          if (matchingProduct) {
            octoProductId = String(matchingProduct.id);
            console.log(`✅ Found matching OCTO product: ${octoProductId}`);

            // Use the first option from this product
            if (matchingProduct.options && matchingProduct.options.length > 0) {
              optionToUse = matchingProduct.options[0];
              octoOptionId = String(optionToUse.id);
              console.log(`✅ Using OCTO option: ${octoOptionId}`);
            }
          } else {
            // If no exact match, try the first product as fallback
            console.log(`⚠️ No exact match found. Trying first product as fallback.`);
            octoProductId = String(firstProduct.id);
            if (firstProduct.options && firstProduct.options.length > 0) {
              optionToUse = firstProduct.options[0];
              octoOptionId = String(optionToUse.id);
            }
            console.log(`📦 Using fallback: productId=${octoProductId}, optionId=${octoOptionId}`);
          }

          // Extract unit IDs from the option
          if (optionToUse && optionToUse.units && optionToUse.units.length > 0) {
            octoUnitIds = optionToUse.units.map(u => String(u.id));
            defaultUnitId = octoUnitIds[0]; // Use first unit as default
            console.log(`📦 Available unit IDs: ${octoUnitIds.join(', ')}`);
            console.log(`📦 Default unit ID: ${defaultUnitId}`);
          }
        }
      } catch (e) {
        console.log(`⚠️ Could not fetch OCTO products: ${e.message}`);
      }

      // Step 1: Get availability for the new date using OCTO IDs
      console.log(`🔍 Checking availability for ${newDate} with productId=${octoProductId}, optionId=${octoOptionId}...`);
      const availabilityResult = await octoRequest('POST', '/availability', {
        productId: octoProductId,
        optionId: octoOptionId,
        localDate: newDate,  // Format: YYYY-MM-DD
      });

      console.log(`📅 Found ${Array.isArray(availabilityResult) ? availabilityResult.length : 0} availability slots`);

      if (!Array.isArray(availabilityResult) || availabilityResult.length === 0) {
        throw new Error(`No availability found for ${newDate}. The tour may be fully booked or not running on this date.`);
      }

      // Use the first available slot (or could match by time)
      const newAvailability = availabilityResult[0];
      const availabilityId = newAvailability.id;

      console.log(`✅ Found availability: ${availabilityId}`);

      // Step 2: Get the booking UUID from OCTO (needed for PATCH)
      // First try to get the booking details via OCTO
      console.log(`🔍 Looking up booking in OCTO...`);

      // The OCTO booking UUID might be stored in the booking or we need to search
      // Let's try using the confirmation code to find it
      let octoBookingUuid = null;

      // Try to get OCTO booking by supplier reference (Bokun booking ID)
      try {
        const octoBookings = await octoRequest('GET', `/bookings?supplierReference=${bookingId}`);
        if (Array.isArray(octoBookings) && octoBookings.length > 0) {
          octoBookingUuid = octoBookings[0].uuid;
          console.log(`✅ Found OCTO booking UUID: ${octoBookingUuid}`);
        }
      } catch (e) {
        console.log(`⚠️ Could not find OCTO booking: ${e.message}`);
      }

      if (!octoBookingUuid) {
        // OCTO booking not found - this is a portal-created booking
        // Strategy: Cancel old booking + Create new booking via OCTO
        console.log(`⚠️ OCTO booking not found - using cancel + rebook strategy`);

        // Extract customer info for new booking
        const customer = foundBooking.customer || {};
        const customerContact = {
          fullName: `${customer.firstName || ''} ${customer.lastName || ''}`.trim(),
          firstName: customer.firstName || '',
          lastName: customer.lastName || '',
          emailAddress: customer.email || customer.emailAddress || '',
          phoneNumber: customer.phoneNumber || customer.phone || '',
          country: customer.countryCode || customer.nationality || 'IS',
        };

        // Extract unit items (participants) from original booking
        // Use the OCTO default unit ID, not the Bokun price category IDs
        const unitItems = [];
        let totalParticipants = 0;

        for (const pcb of (productBooking.priceCategoryBookings || [])) {
          const quantity = pcb.persons || pcb.qty || 1;
          totalParticipants += quantity;
        }

        // If we couldn't count participants, default to 1
        if (totalParticipants === 0) {
          totalParticipants = productBooking.totalParticipants || foundBooking.totalParticipants || 1;
        }

        // Create unit items using the OCTO default unit ID
        const unitIdToUse = defaultUnitId || octoUnitIds[0] || octoOptionId;
        for (let i = 0; i < totalParticipants; i++) {
          unitItems.push({ unitId: unitIdToUse });
        }

        // Extract pickup info from original booking
        const fields = productBooking.fields || {};
        let pickupLocation = null;
        let pickupLocationId = null;

        // Try pickupPlace object first (predefined locations)
        if (fields.pickupPlace) {
          const pp = fields.pickupPlace;
          pickupLocation = pp.title || pp.name || pp.description || null;
          pickupLocationId = pp.id ? String(pp.id) : null;
        }
        // Then try pickupPlaceDescription (free text)
        if (!pickupLocation && fields.pickupPlaceDescription) {
          pickupLocation = fields.pickupPlaceDescription;
        }
        // Also check productBooking.pickupPlace directly
        if (!pickupLocation && productBooking.pickupPlace) {
          const pp = productBooking.pickupPlace;
          pickupLocation = pp.title || pp.name || pp.description || null;
          pickupLocationId = pp.id ? String(pp.id) : null;
        }

        console.log(`📋 Customer: ${customerContact.fullName}, Email: ${customerContact.emailAddress}`);
        console.log(`📋 Total participants: ${totalParticipants}, Unit ID: ${unitIdToUse}`);
        console.log(`📋 Unit items: ${JSON.stringify(unitItems)}`);
        console.log(`📋 Pickup: ${pickupLocation || 'None'} (ID: ${pickupLocationId || 'None'})`);

        // Step 2a: Cancel the existing booking
        // Use the correct Bokun cancel endpoint format with confirmation code
        const bookingConfirmCode = confirmationCode || foundBooking.confirmationCode;
        console.log(`🚫 Cancelling existing booking ${bookingId} (${bookingConfirmCode})...`);

        const cancelPath = `/booking.json/cancel-booking/${bookingConfirmCode}`;
        const cancelDate = new Date().toISOString().replace('T', ' ').substring(0, 19);
        const cancelMessage = cancelDate + accessKey + 'POST' + cancelPath;
        const cancelSignature = crypto
          .createHmac('sha1', secretKey)
          .update(cancelMessage)
          .digest('base64');

        const cancelResult = await new Promise((resolve, reject) => {
          const cancelBody = JSON.stringify({
            reason: `Rescheduled to ${newDate}. ${reason || 'Rescheduled via admin app'}`,
          });

          const options = {
            hostname: 'api.bokun.io',
            path: cancelPath,
            method: 'POST',
            headers: {
              'Content-Type': 'application/json;charset=UTF-8',
              'Content-Length': Buffer.byteLength(cancelBody),
              'X-Bokun-AccessKey': accessKey,
              'X-Bokun-Date': cancelDate,
              'X-Bokun-Signature': cancelSignature,
            },
          };

          const apiReq = https.request(options, (apiRes) => {
            let data = '';
            apiRes.on('data', (chunk) => { data += chunk; });
            apiRes.on('end', () => {
              console.log(`🚫 Cancel response: ${apiRes.statusCode}`);
              if (apiRes.statusCode >= 200 && apiRes.statusCode < 400) {
                resolve({ success: true, statusCode: apiRes.statusCode });
              } else {
                reject(new Error(`Cancel failed: ${apiRes.statusCode} - ${data}`));
              }
            });
          });

          apiReq.on('error', (error) => reject(error));
          apiReq.write(cancelBody);
          apiReq.end();
        });

        console.log(`✅ Booking cancelled successfully`);

        // Step 2b: Create new booking via OCTO
        console.log(`📝 Creating new booking for ${newDate}...`);

        const newBookingRequest = {
          productId: octoProductId,
          optionId: octoOptionId,
          availabilityId: availabilityId,
          unitItems: unitItems.length > 0 ? unitItems : [{ unitId: defaultUnitId || octoUnitIds[0] }],
          notes: `Rebook from ${confirmationCode || bookingId}. Original date: ${currentDate}. ${pickupLocation ? 'Pickup: ' + pickupLocation + '. ' : ''}Reason: ${reason || 'Customer request'}`,
        };

        console.log(`📤 New booking request: ${JSON.stringify(newBookingRequest)}`);

        const newBooking = await octoRequest('POST', '/bookings', newBookingRequest);

        console.log(`✅ New booking created: ${newBooking.uuid || newBooking.id || 'unknown'}`);

        // Confirm the booking with contact details and pickup info
        if (newBooking.uuid) {
          console.log(`✔️ Confirming new booking with contact details...`);
          const confirmRequest = {
            contact: {
              firstName: customerContact.firstName || 'Guest',
              lastName: customerContact.lastName || 'Customer',
              emailAddress: customerContact.emailAddress || 'no-email@placeholder.com',
              phoneNumber: customerContact.phoneNumber || '',
            },
          };
          // Note: Bokun OCTO confirm only supports: contact, resellerReference, emailReceipt, unitItems
          // Pickup info is preserved in the booking notes field instead

          console.log(`📤 Confirm request: ${JSON.stringify(confirmRequest)}`);
          await octoRequest('POST', `/bookings/${newBooking.uuid}/confirm`, confirmRequest);
          console.log(`✅ Booking confirmed!`);

          // Step 2c: Update pickup location via Bokun REST API (OCTO doesn't support pickup)
          // Uses SAME method as updatePickupLocation function - search for booking to get productBookingId
          if (pickupLocation && pickupLocationId) {
            console.log(`📍 Setting pickup location via REST API: ${pickupLocation} (ID: ${pickupLocationId})`);

            // Wait for Bokun to process the new booking
            await new Promise(resolve => setTimeout(resolve, 2000));

            // Search for the new booking by confirmation code to get productBookingId
            const newConfirmationCode = newBooking.supplierReference;
            // Extract numeric ID from confirmation code (e.g., AUR-82247617 -> 82247617)
            const newBookingId = newConfirmationCode.replace(/[^0-9]/g, '');
            console.log(`🔍 Searching for new booking: ${newConfirmationCode} (ID: ${newBookingId})`);

            const searchPath2 = '/booking.json/booking-search';
            const searchDate2 = new Date().toISOString().replace('T', ' ').substring(0, 19);
            const searchMessage2 = searchDate2 + accessKey + 'POST' + searchPath2;
            const searchSignature2 = crypto
              .createHmac('sha1', secretKey)
              .update(searchMessage2)
              .digest('base64');

            let actualProductBookingId = null;
            try {
              const searchResult2 = await new Promise((resolve, reject) => {
                // Use bookingId search like updatePickupLocation does
                const searchBody = JSON.stringify({ bookingId: parseInt(newBookingId) });
                const options = {
                  hostname: 'api.bokun.io',
                  path: searchPath2,
                  method: 'POST',
                  headers: {
                    'Content-Type': 'application/json;charset=UTF-8',
                    'Content-Length': Buffer.byteLength(searchBody),
                    'X-Bokun-AccessKey': accessKey,
                    'X-Bokun-Date': searchDate2,
                    'X-Bokun-Signature': searchSignature2,
                  },
                };

                const apiReq = https.request(options, (apiRes) => {
                  let data = '';
                  apiRes.on('data', (chunk) => { data += chunk; });
                  apiRes.on('end', () => {
                    if (apiRes.statusCode >= 200 && apiRes.statusCode < 300) {
                      resolve(JSON.parse(data));
                    } else {
                      reject(new Error(`Search failed: ${apiRes.statusCode}`));
                    }
                  });
                });
                apiReq.on('error', reject);
                apiReq.write(searchBody);
                apiReq.end();
              });

              const newBokunBooking = searchResult2.items?.[0];
              if (newBokunBooking) {
                actualProductBookingId = newBokunBooking.productBookings?.[0]?.id;
                console.log(`📋 Found productBookingId: ${actualProductBookingId}`);
              }
            } catch (e) {
              console.log(`⚠️ Could not search for new booking: ${e.message}`);
            }

            // Apply pickup using ActivityPickupAction (same as updatePickupLocation)
            if (actualProductBookingId) {
              const editPath = '/booking.json/edit';
              const editDate = new Date().toISOString().replace('T', ' ').substring(0, 19);
              const editMessage = editDate + accessKey + 'POST' + editPath;
              const editSignature = crypto
                .createHmac('sha1', secretKey)
                .update(editMessage)
                .digest('base64');

              // ActivityPickupAction - body must be an ARRAY directly
              const editActions = [{
                type: 'ActivityPickupAction',
                activityBookingId: parseInt(actualProductBookingId),
                pickup: true,
                pickupPlaceId: parseInt(pickupLocationId),
                description: pickupLocation,
              }];

              console.log(`📤 Edit request: ${JSON.stringify(editActions)}`);

              try {
                const editResult = await new Promise((resolve, reject) => {
                  const editBody = JSON.stringify(editActions);
                  const options = {
                    hostname: 'api.bokun.io',
                    path: editPath,
                    method: 'POST',
                    headers: {
                      'Content-Type': 'application/json;charset=UTF-8',
                      'Content-Length': Buffer.byteLength(editBody),
                      'X-Bokun-AccessKey': accessKey,
                      'X-Bokun-Date': editDate,
                      'X-Bokun-Signature': editSignature,
                    },
                  };

                  const apiReq = https.request(options, (apiRes) => {
                    let data = '';
                    apiRes.on('data', (chunk) => { data += chunk; });
                    apiRes.on('end', () => {
                      console.log(`📍 Edit pickup response: ${apiRes.statusCode}`);
                      if (apiRes.statusCode >= 200 && apiRes.statusCode < 400) {
                        resolve({ success: true });
                      } else {
                        console.log(`⚠️ Edit pickup failed: ${data}`);
                        resolve({ success: false, error: data });
                      }
                    });
                  });

                  apiReq.on('error', (error) => {
                    resolve({ success: false, error: error.message });
                  });
                  apiReq.write(editBody);
                  apiReq.end();
                });

                if (editResult.success) {
                  console.log(`✅ Pickup location set successfully!`);
                } else {
                  console.log(`⚠️ Pickup location not set - booking still created`);
                }
              } catch (e) {
                console.log(`⚠️ Could not set pickup: ${e.message}`);
              }
            } else {
              console.log(`⚠️ Could not find productBookingId - pickup not set`);
            }
          }
        }

        // Log success
        await admin.firestore().collection('booking_actions').add({
          bookingId,
          confirmationCode: confirmationCode || foundBooking.confirmationCode,
          customerName,
          action: 'reschedule',
          performedBy: userId || 'unknown',
          performedAt: admin.firestore.FieldValue.serverTimestamp(),
          reason: reason || 'Rescheduled via admin app',
          originalData: { date: currentDate },
          newData: {
            date: newDate,
            availabilityId,
            newBookingUuid: newBooking.uuid,
            newBookingId: newBooking.id,
          },
          success: true,
          method: 'cancel_and_rebook',
          source: 'octo_api',
        });

        await snapshot.ref.update({
          status: 'completed',
          method: 'cancel_and_rebook',
          availabilityId,
          newBookingUuid: newBooking.uuid || null,
          newBookingId: newBooking.id || null,
          customerName,
          originalDate: currentDate,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
          message: `Booking rescheduled to ${newDate} via cancel + rebook`,
        });

        console.log(`✅ Reschedule completed via cancel + rebook: ${requestId}`);
        return;
      }

      // Step 3: PATCH the booking with new availability
      console.log(`📝 Updating booking ${octoBookingUuid} to new date...`);

      const updateResult = await octoRequest('PATCH', `/bookings/${octoBookingUuid}`, {
        availabilityId: availabilityId,
        // Preserve the unit items from the original booking
        unitItems: productBooking.priceCategoryBookings?.map(pcb => ({
          unitId: pcb.priceCategoryBooking?.priceCategory?.id || pcb.id,
        })) || [],
      });

      console.log(`✅ Booking updated successfully via OCTO API!`);

      // Log success
      await admin.firestore().collection('booking_actions').add({
        bookingId,
        confirmationCode: confirmationCode || foundBooking.confirmationCode,
        customerName,
        action: 'reschedule',
        performedBy: userId || 'unknown',
        performedAt: admin.firestore.FieldValue.serverTimestamp(),
        reason: reason || 'Rescheduled via admin app',
        originalData: { date: currentDate },
        newData: { date: newDate, availabilityId },
        success: true,
        source: 'octo_api',
      });

      // Mark request as completed
      await snapshot.ref.update({
        status: 'completed',
        availabilityId,
        customerName,
        originalDate: currentDate,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        message: `Booking rescheduled to ${newDate}`,
      });

      console.log(`✅ Reschedule completed: ${requestId}`);
    } catch (error) {
      console.error(`❌ Reschedule failed: ${error.message}`);

      // Log failure
      await admin.firestore().collection('booking_actions').add({
        bookingId,
        confirmationCode: confirmationCode || '',
        action: 'reschedule',
        performedBy: userId || 'unknown',
        performedAt: admin.firestore.FieldValue.serverTimestamp(),
        reason: reason || 'Attempted reschedule',
        newData: { date: newDate },
        success: false,
        errorMessage: error.message,
        source: 'firestore_trigger',
      });

      // Mark request as failed
      await snapshot.ref.update({
        status: 'failed',
        error: error.message,
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }
);

/**
 * Firestore Trigger: Check availability for a booking reschedule
 * Returns available time slots for a given date so Flutter can display them
 */
exports.checkRescheduleAvailability = onDocumentCreated(
  {
    document: 'availability_checks/{checkId}',
    region: 'us-central1',
    secrets: ['BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY', 'BOKUN_OCTO_TOKEN'],
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const data = snapshot.data();
    const { bookingId, targetDate, confirmationCode } = data;
    const checkId = event.params.checkId;

    console.log(`🔍 Checking availability for booking ${bookingId} on ${targetDate}`);

    await snapshot.ref.update({ status: 'processing' });

    try {
      const accessKey = process.env.BOKUN_ACCESS_KEY;
      const secretKey = process.env.BOKUN_SECRET_KEY;
      const octoToken = process.env.BOKUN_OCTO_TOKEN;

      if (!octoToken) {
        throw new Error('OCTO token not configured');
      }

      // First, find the booking to get product details
      const now = new Date();
      const bokunDate = now.toISOString().replace('T', ' ').substring(0, 19);
      const searchPath = '/booking.json/booking-search';
      const message = bokunDate + accessKey + 'POST' + searchPath;
      const signature = crypto
        .createHmac('sha1', secretKey)
        .update(message)
        .digest('base64');

      const searchResult = await new Promise((resolve, reject) => {
        const postData = JSON.stringify({ id: parseInt(bookingId), limit: 10 });
        const options = {
          hostname: 'api.bokun.io',
          path: searchPath,
          method: 'POST',
          headers: {
            'Content-Type': 'application/json;charset=UTF-8',
            'Content-Length': Buffer.byteLength(postData),
            'X-Bokun-AccessKey': accessKey,
            'X-Bokun-Date': bokunDate,
            'X-Bokun-Signature': signature,
          },
        };

        const apiReq = https.request(options, (apiRes) => {
          let data = '';
          apiRes.on('data', (chunk) => { data += chunk; });
          apiRes.on('end', () => {
            if (apiRes.statusCode >= 200 && apiRes.statusCode < 300) {
              resolve(JSON.parse(data));
            } else {
              reject(new Error(`Search error: ${apiRes.statusCode}`));
            }
          });
        });
        apiReq.on('error', reject);
        apiReq.write(postData);
        apiReq.end();
      });

      const foundBooking = searchResult.items?.find(b => String(b.id) === String(bookingId));
      if (!foundBooking) {
        throw new Error('Booking not found');
      }

      const productBooking = foundBooking.productBookings?.[0];
      const productId = productBooking?.product?.id;

      // Log complete productBooking structure to find correct optionId
      console.log(`📋 Full productBooking structure: ${JSON.stringify(productBooking, null, 2).substring(0, 2000)}`);

      // Try to get the correct optionId - might be the activity ID or a specific rate
      const optionId = productBooking?.activity?.id || productBooking?.rate?.id || productId;

      console.log(`📦 Product ID: ${productId}, Option ID: ${optionId}`);

      // Query OCTO API for availability
      const availabilityResult = await new Promise((resolve, reject) => {
        const body = JSON.stringify({
          productId: String(productId),
          optionId: String(optionId),
          localDate: targetDate,
        });

        console.log(`📡 OCTO availability request: ${body}`);

        const options = {
          hostname: 'api.bokun.io',
          path: '/octo/v1/availability',
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(body),
            'Authorization': `Bearer ${octoToken}`,
          },
        };

        const apiReq = https.request(options, (apiRes) => {
          let data = '';
          apiRes.on('data', (chunk) => { data += chunk; });
          apiRes.on('end', () => {
            console.log(`📡 OCTO availability response: ${apiRes.statusCode} - ${data.substring(0, 500)}`);
            if (apiRes.statusCode >= 200 && apiRes.statusCode < 300) {
              try {
                resolve(JSON.parse(data));
              } catch (e) {
                resolve([]);
              }
            } else {
              // Log as error but don't throw - return empty availability
              console.error(`OCTO error: ${data}`);
              resolve([]);
            }
          });
        });
        apiReq.on('error', (e) => {
          console.error(`OCTO request error: ${e.message}`);
          resolve([]);
        });
        apiReq.write(body);
        apiReq.end();
      });

      // Format available slots for Flutter UI
      const slots = (Array.isArray(availabilityResult) ? availabilityResult : []).map(slot => ({
        id: slot.id,
        localDateTimeStart: slot.localDateTimeStart,
        localDateTimeEnd: slot.localDateTimeEnd,
        available: slot.available,
        status: slot.status,
        vacancies: slot.vacancies,
      }));

      console.log(`📅 Found ${slots.length} availability slots`);

      await snapshot.ref.update({
        status: 'completed',
        productId,
        optionId,
        currentDate: productBooking?.startDate,
        customerName: foundBooking.customer?.firstName
          ? `${foundBooking.customer.firstName} ${foundBooking.customer.lastName || ''}`.trim()
          : 'Unknown',
        slots,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    } catch (error) {
      console.error(`❌ Availability check failed: ${error.message}`);
      await snapshot.ref.update({
        status: 'failed',
        error: error.message,
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }
);

/**
 * Get pickup places for an activity/product
 */
exports.getPickupPlaces = onRequest(
  {
    cors: true,
    secrets: ['BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY'],
  },
  async (req, res) => {
    if (req.method !== 'GET' && req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }

    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    const idToken = authHeader.split('Bearer ')[1];
    try {
      await admin.auth().verifyIdToken(idToken);
    } catch (error) {
      res.status(401).json({ error: 'Invalid token' });
      return;
    }

    // Get productId from query or body
    const productId = req.query.productId || req.body.productId;
    if (!productId) {
      res.status(400).json({ error: 'productId is required' });
      return;
    }

    const accessKey = process.env.BOKUN_ACCESS_KEY;
    const secretKey = process.env.BOKUN_SECRET_KEY;

    if (!accessKey || !secretKey) {
      res.status(500).json({ error: 'Bokun API keys not configured' });
      return;
    }

    try {
      console.log(`📍 Fetching pickup places for product ${productId}`);

      const pickupPath = `/activity.json/${productId}/pickup-places`;
      const pickupDate = new Date().toISOString().replace('T', ' ').substring(0, 19);
      const pickupMessage = pickupDate + accessKey + 'GET' + pickupPath;
      const pickupSignature = crypto
        .createHmac('sha1', secretKey)
        .update(pickupMessage)
        .digest('base64');

      const pickupPlaces = await new Promise((resolve, reject) => {
        const options = {
          hostname: 'api.bokun.io',
          path: pickupPath,
          method: 'GET',
          headers: {
            'X-Bokun-AccessKey': accessKey,
            'X-Bokun-Date': pickupDate,
            'X-Bokun-Signature': pickupSignature,
          },
        };

        const apiReq = https.request(options, (apiRes) => {
          let data = '';
          apiRes.on('data', (chunk) => { data += chunk; });
          apiRes.on('end', () => {
            console.log(`📍 Pickup places response: ${apiRes.statusCode}`);
            console.log(`📍 Raw response: ${data.substring(0, 500)}`);
            if (apiRes.statusCode >= 200 && apiRes.statusCode < 300) {
              try {
                const parsed = JSON.parse(data);
                console.log(`📍 Response type: ${typeof parsed}, isArray: ${Array.isArray(parsed)}`);
                // Check for nested structures
                if (parsed.pickupPlaces) {
                  resolve(parsed.pickupPlaces);
                } else if (parsed.pickupDropoffPlaces) {
                  resolve(parsed.pickupDropoffPlaces);
                } else if (parsed.items) {
                  resolve(parsed.items);
                } else {
                  resolve(parsed);
                }
              } catch (e) {
                reject(new Error('Failed to parse pickup places response'));
              }
            } else {
              reject(new Error(`Bokun API error: ${apiRes.statusCode} - ${data}`));
            }
          });
        });

        apiReq.on('error', (error) => {
          reject(error);
        });
        apiReq.end();
      });

      // Format the pickup places for the UI
      const places = (Array.isArray(pickupPlaces) ? pickupPlaces : []).map(place => ({
        id: place.id,
        title: place.title || place.name,
        address: place.address?.streetAddress || place.address || '',
        city: place.address?.city || '',
        type: place.type || 'HOTEL',
      }));

      console.log(`✅ Found ${places.length} pickup places`);
      res.json({ pickupPlaces: places });

    } catch (error) {
      console.error(`❌ Error fetching pickup places: ${error.message}`);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * Update pickup location on an existing booking
 * Uses Bokun GraphQL API since REST API booking.json/edit has issues with action types
 */
exports.updatePickupLocation = onRequest(
  {
    cors: true,
    secrets: ['BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY'],
  },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }

    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    const idToken = authHeader.split('Bearer ')[1];
    try {
      await admin.auth().verifyIdToken(idToken);
    } catch (error) {
      res.status(401).json({ error: 'Invalid token' });
      return;
    }

    const { bookingId, productBookingId, pickupPlaceId, pickupPlaceName } = req.body;

    if (!bookingId || !pickupPlaceId) {
      res.status(400).json({ error: 'bookingId and pickupPlaceId are required' });
      return;
    }

    const accessKey = process.env.BOKUN_ACCESS_KEY;
    const secretKey = process.env.BOKUN_SECRET_KEY;

    if (!accessKey || !secretKey) {
      res.status(500).json({ error: 'Bokun API keys not configured' });
      return;
    }

    try {
      console.log(`📍 Updating pickup for booking ${bookingId} to place ${pickupPlaceId} (${pickupPlaceName})`);

      // First, get the booking to find the productBookingId if not provided
      let actualProductBookingId = productBookingId;

      if (!actualProductBookingId) {
        // Search for the booking to get productBookingId
        const searchPath = '/booking.json/booking-search';
        const searchDate = new Date().toISOString().replace('T', ' ').substring(0, 19);
        const searchMessage = searchDate + accessKey + 'POST' + searchPath;
        const searchSignature = crypto
          .createHmac('sha1', secretKey)
          .update(searchMessage)
          .digest('base64');

        const searchResult = await new Promise((resolve, reject) => {
          const searchBody = JSON.stringify({ bookingId: parseInt(bookingId) });
          const options = {
            hostname: 'api.bokun.io',
            path: searchPath,
            method: 'POST',
            headers: {
              'Content-Type': 'application/json;charset=UTF-8',
              'Content-Length': Buffer.byteLength(searchBody),
              'X-Bokun-AccessKey': accessKey,
              'X-Bokun-Date': searchDate,
              'X-Bokun-Signature': searchSignature,
            },
          };

          const apiReq = https.request(options, (apiRes) => {
            let data = '';
            apiRes.on('data', (chunk) => { data += chunk; });
            apiRes.on('end', () => {
              if (apiRes.statusCode >= 200 && apiRes.statusCode < 300) {
                resolve(JSON.parse(data));
              } else {
                reject(new Error(`Search failed: ${apiRes.statusCode}`));
              }
            });
          });
          apiReq.on('error', reject);
          apiReq.write(searchBody);
          apiReq.end();
        });

        const booking = searchResult.items?.find(b => String(b.id) === String(bookingId));
        if (!booking) {
          throw new Error(`Booking ${bookingId} not found`);
        }
        actualProductBookingId = booking.productBookings?.[0]?.id;
        console.log(`📋 Found productBookingId: ${actualProductBookingId}`);
      }

      if (!actualProductBookingId) {
        throw new Error('Could not find productBookingId');
      }

      // Use REST API with ActivityPickupAction - body must be an ARRAY directly
      const editPath = '/booking.json/edit';
      const editDate = new Date().toISOString().replace('T', ' ').substring(0, 19);
      const editMessage = editDate + accessKey + 'POST' + editPath;
      const editSignature = crypto
        .createHmac('sha1', secretKey)
        .update(editMessage)
        .digest('base64');

      // ActivityPickupAction - the body is an ARRAY of actions directly (NOT wrapped in { actions: [...] })
      const editActions = [{
        type: 'ActivityPickupAction',
        activityBookingId: parseInt(actualProductBookingId),
        pickup: true,
        pickupPlaceId: parseInt(pickupPlaceId),
        description: pickupPlaceName || '',
      }];

      console.log(`📤 Edit request: ${JSON.stringify(editActions)}`);

      const editResult = await new Promise((resolve, reject) => {
        const editBody = JSON.stringify(editActions);
        const options = {
          hostname: 'api.bokun.io',
          path: editPath,
          method: 'POST',
          headers: {
            'Content-Type': 'application/json;charset=UTF-8',
            'Content-Length': Buffer.byteLength(editBody),
            'X-Bokun-AccessKey': accessKey,
            'X-Bokun-Date': editDate,
            'X-Bokun-Signature': editSignature,
          },
        };

        const apiReq = https.request(options, (apiRes) => {
          let data = '';
          apiRes.on('data', (chunk) => { data += chunk; });
          apiRes.on('end', () => {
            console.log(`📍 Edit response: ${apiRes.statusCode} - ${data.substring(0, 500)}`);
            if (apiRes.statusCode >= 200 && apiRes.statusCode < 300) {
              try {
                resolve(JSON.parse(data));
              } catch (e) {
                resolve({ success: true, raw: data });
              }
            } else {
              reject(new Error(`Edit failed: ${apiRes.statusCode} - ${data}`));
            }
          });
        });
        apiReq.on('error', reject);
        apiReq.write(editBody);
        apiReq.end();
      });

      console.log(`✅ Pickup updated successfully`);

      // Log the action
      await admin.firestore().collection('booking_actions').add({
        bookingId,
        action: 'update_pickup',
        pickupPlaceId,
        pickupPlaceName: pickupPlaceName || '',
        performedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      res.json({
        success: true,
        message: `Pickup updated to ${pickupPlaceName || pickupPlaceId}`,
        result: editResult,
      });

    } catch (error) {
      console.error(`❌ Error updating pickup: ${error.message}`);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * Cancel a booking
 */
exports.cancelBooking = onRequest(
  {
    cors: true,
    secrets: ['BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY'],

  },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }

    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      res.status(401).json({ error: 'Unauthorized - missing token' });
      return;
    }

    try {
      const token = authHeader.split('Bearer ')[1];
      const decodedToken = await admin.auth().verifyIdToken(token);
      const uid = decodedToken.uid;

      const requestData = req.body.data || req.body;
      const { bookingId, confirmationCode, reason } = requestData;

      if (!bookingId) {
        res.status(400).json({ error: 'bookingId is required' });
        return;
      }

      if (!reason) {
        res.status(400).json({ error: 'reason is required for cancellation' });
        return;
      }

      const accessKey = process.env.BOKUN_ACCESS_KEY;
      const secretKey = process.env.BOKUN_SECRET_KEY;

      if (!accessKey || !secretKey) {
        res.status(500).json({ error: 'Bokun API keys not configured' });
        return;
      }

      // Get current booking for logging
      let currentBooking = null;
      try {
        currentBooking = await makeBokunRequest(
          'GET',
          `/booking.json/${bookingId}`,
          null,
          accessKey,
          secretKey
        );
      } catch (e) {
        console.warn('Could not fetch booking details for logging:', e.message);
      }

      if (!confirmationCode) {
        res.status(400).json({ error: 'confirmationCode is required for cancellation' });
        return;
      }

      // Cancel the booking using correct endpoint
      const cancelRequest = {
        note: reason,
        notify: true,
      };

      const result = await makeBokunRequest(
        'POST',
        `/booking.json/cancel-booking/${confirmationCode}`,
        cancelRequest,
        accessKey,
        secretKey
      );

      // Log the action
      await admin.firestore().collection('booking_actions').add({
        bookingId,
        confirmationCode: confirmationCode || '',
        action: 'cancel',
        performedBy: uid,
        performedAt: admin.firestore.FieldValue.serverTimestamp(),
        reason,
        originalData: currentBooking ? {
          date: currentBooking.startDate,
          status: currentBooking.status,
          totalParticipants: currentBooking.totalParticipants,
        } : null,
        success: true,
        source: 'cloud_function',
      });

      res.status(200).json({ result, success: true });
    } catch (error) {
      console.error('Error in cancelBooking:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

// Helper: Make authenticated request to Bokun API
async function makeBokunRequest(method, path, body, accessKey, secretKey) {
  const now = new Date();
  const bokunDate = now.toISOString().replace('T', ' ').substring(0, 19);

  // Create HMAC-SHA1 signature
  const message = bokunDate + accessKey + method + path;
  const signature = crypto
    .createHmac('sha1', secretKey)
    .update(message)
    .digest('base64');

  console.log(`📡 Bokun API Request: ${method} ${path}`);
  console.log(`📅 Date: ${bokunDate}`);
  if (body) {
    console.log(`📦 Body: ${JSON.stringify(body)}`);
  }

  const options = {
    hostname: 'api.bokun.io',
    path: path,
    method: method,
    headers: {
      'Content-Type': 'application/json;charset=UTF-8',
      'X-Bokun-AccessKey': accessKey,
      'X-Bokun-Date': bokunDate,
      'X-Bokun-Signature': signature,
    },
  };

  // Add Content-Length header for POST requests (matching getBookings function)
  const postData = body ? JSON.stringify(body) : null;
  if (postData) {
    options.headers['Content-Length'] = Buffer.byteLength(postData);
  }

  return new Promise((resolve, reject) => {
    const apiReq = https.request(options, (apiRes) => {
      let data = '';

      // Log response details for debugging
      console.log(`📡 Bokun API Response: ${apiRes.statusCode}`);
      console.log(`📡 Response Headers: ${JSON.stringify(apiRes.headers)}`);

      // Handle redirects
      if (apiRes.statusCode === 301 || apiRes.statusCode === 302 || apiRes.statusCode === 303) {
        console.log(`🔄 Redirect detected! Location: ${apiRes.headers.location}`);
      }

      apiRes.on('data', (chunk) => {
        data += chunk;
      });

      apiRes.on('end', () => {
        console.log(`📡 Response Body: ${data.substring(0, 500)}`);

        if (apiRes.statusCode >= 200 && apiRes.statusCode < 300) {
          try {
            const jsonData = JSON.parse(data);
            resolve(jsonData);
          } catch (e) {
            resolve(data); // Return raw data if not JSON
          }
        } else {
          reject(new Error(`Bokun API error: ${apiRes.statusCode} - ${data}`));
        }
      });
    });

    apiReq.on('error', (error) => {
      reject(error);
    });

    if (postData) {
      apiReq.write(postData);
    }
    apiReq.end();
  });
}

// ============================================
// AI BOOKING ASSIST - Generate personalized replies with booking context
// ============================================
// This function is called on-demand when staff clicks "AI Assist" in the inbox
// It looks up customer bookings, understands their intent, and suggests a reply + action

const AI_SYSTEM_PROMPT = `You are Aurora Viking Staff AI, a trusted senior team member at Aurora Viking.

ABOUT AURORA VIKING:
- Premium Northern Lights tour operator in Reykjavik, Iceland
- Tours run from September through the end of April (aurora season)
- Pickup from hotels and designated bus stops in Reykjavik area
- Tours last 4-5 hours depending on conditions
- Small groups, expert guides, quality-focused

PICKUP LOCATIONS (Reykjavik only - we do NOT pick up outside Reykjavik):
- Bus Stop #1 - Ráðhúsið - City Hall
- Bus Stop #3 - Lækjargata
- Bus Stop #4
- Bus stop #5
- Bus stop #6 - Culture House
- Bus Stop #8 - Hallgrimstorg
- Bus Stop #9
- Bus Stop #12, #13, #14, #15
- BSI Bus Terminal
- Skarfabakki Harbour / Cruise port (pickup 15 min earlier)
- Hotels: Hilton Reykjavik Nordica, Grand Hotel Reykjavik, The Reykjavik EDITION, Fosshotel Baron, Hotel Klettur, Hotel Cabin, Exeter Hotel, Alva Hotel, Eyja Guldsmeden, Hotel Island Spa & Wellness, Reykjavik Natura, Reykjavik Lights by Keahotels, Oddsson Hotel, Kex Hostel, Bus Hostel, Dalur HI Hostel, and many more
- If customer is staying OUTSIDE Reykjavik (e.g., Garðabær, Kópavogur, Hafnarfjörður), recommend they come to a bus stop in central Reykjavik or BSI terminal

COMMUNICATION STYLE:
- Be professional, calm, and confident
- No excessive enthusiasm or emojis
- Direct answers first, context second
- Responses should be SHORT: 2-3 sentences max unless details are truly needed
- Use customer's name when known
- Reference their booking details when relevant
- Slightly Icelandic directness (polite, not American-corporate)

BOOKING ACTIONS YOU CAN SUGGEST:
1. RESCHEDULE - Customer wants to change their tour date
2. CANCEL - Customer wants to cancel and get a refund
3. CHANGE_PICKUP - Customer wants to change pickup location
4. INFO_ONLY - No booking change needed, just information

POLICIES (CRITICAL - FOLLOW EXACTLY):
- UNLIMITED FREE RETRY: If tour operates and no Northern Lights seen with naked eye, guests get unlimited free retries for 2 years
- NO REFUNDS for no lights seen - only retry option
- Guests MUST attend original booking to qualify for retry
- Retry bookings must be made BEFORE 12:00 noon on tour day, subject to availability
- Rescheduling within 24 hours of departure = treated as cancellation = NON-REFUNDABLE
- If we allow a courtesy reschedule, it becomes FINAL (non-refundable, no further changes)
- If AURORA VIKING cancels (weather, safety): guests choose free rebooking OR full refund

NEVER SAY:
- NEVER mention cash or payment unless customer specifically asks about payment
- NEVER offer percentage refunds (we don't do 50% refunds, etc.)
- NEVER promise refunds for no Northern Lights
- NEVER guarantee seats for retry on specific nights
- For complex refund/cancellation requests, say you'll check with the team

OUTPUT FORMAT (JSON):
{
  "suggestedReply": "Your response to the customer...",
  "suggestedAction": {
    "type": "RESCHEDULE|CANCEL|CHANGE_PICKUP|INFO_ONLY",
    "bookingId": "booking ID if action needed",
    "confirmationCode": "AUR-XXXXXXXX if found",
    "params": {
      "newDate": "YYYY-MM-DD if reschedule",
      "newPickupLocation": "location name if pickup change",
      "cancelReason": "reason if cancel"
    },
    "humanReadableDescription": "e.g., Reschedule from Jan 15 to Jan 16"
  },
  "confidence": 0.0 to 1.0,
  "reasoning": "Brief explanation of why you suggest this action"
}`;

exports.generateBookingAiAssist = onCall(
  {
    region: 'us-central1',
    secrets: ['ANTHROPIC_API_KEY', 'BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY'],
  },
  async (request) => {
    console.log('🤖 AI Booking Assist requested');

    // Verify user is authenticated
    if (!request.auth) {
      throw new Error('You must be logged in to use AI Assist');
    }

    const { conversationId, messageContent, customerEmail, customerName, bookingRefs } = request.data;

    if (!conversationId || !messageContent) {
      throw new Error('conversationId and messageContent are required');
    }

    try {
      // Step 0: Extract booking references from the message content itself
      // Support multiple booking formats:
      // - AUR-12345678 (Aurora Viking direct)
      // - VIA-76777741 (Viator)
      // - GET-81930966 (GetYourGuide)
      // - TDI-79829623 (TourDesk)
      // - AV-12345678 (shorthand)
      // - External booking refs (alphanumeric like GYGBLHXM9R2Y)
      const bookingPatterns = [
        /\b(?:AUR|VIA|GET|TDI|AV|aur|via|get|tdi|av)[-\s]?(\d{6,10})\b/gi,  // Prefixed booking refs
        /\b(?:booking|confirmation|reference|ref|order)[:\.\s#]*(\d{6,15})\b/gi,  // booking: 12345678
        /\b(\d{8,10})\b/g,  // 8-10 digit numbers (common booking ID length)
        /\b([A-Z0-9]{10,15})\b/g,  // Alphanumeric refs like GYGBLHXM9R2Y (at least 10 chars)
      ];

      const extractedRefs = new Set(bookingRefs || []);
      for (const pattern of bookingPatterns) {
        const matches = messageContent.matchAll(pattern);
        for (const match of matches) {
          const ref = match[1] || match[0];
          const numericRef = ref.replace(/\D/g, ''); // Just the digits
          if (numericRef.length >= 6) { // Only add if at least 6 digits
            extractedRefs.add(numericRef);
            console.log(`🔍 Found booking reference in message: ${ref} -> ${numericRef}`);
          }
        }
      }
      const allBookingRefs = Array.from(extractedRefs);
      console.log(`🔍 Total booking refs to search: ${allBookingRefs.join(', ') || 'none'}`);

      // Step 1: Find related bookings
      console.log('📋 Looking up bookings for:', { customerEmail, customerName, bookingRefs: allBookingRefs });
      const bookings = await findCustomerBookings({
        email: customerEmail,
        name: customerName,
        bookingRefs: allBookingRefs,
      });
      console.log(`📋 Found ${bookings.length} matching bookings`);

      // Step 2: Build context for AI
      const bookingContext = buildBookingContext(bookings);

      // Step 3: Call Claude API
      const Anthropic = require('@anthropic-ai/sdk').default;
      const anthropic = new Anthropic({
        apiKey: process.env.ANTHROPIC_API_KEY,
      });

      const userMessage = `
CUSTOMER MESSAGE:
${messageContent}

CUSTOMER INFO:
- Name: ${customerName || 'Unknown'}
- Email: ${customerEmail || 'Unknown'}

${bookingContext}

Please analyze this customer message and provide a suggested reply and action in JSON format.`;

      console.log('🤖 Calling Claude API...');
      const response = await anthropic.messages.create({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 1024,
        messages: [
          {
            role: 'user',
            content: userMessage,
          },
        ],
        system: AI_SYSTEM_PROMPT,
      });

      // Parse the response
      let aiResult;
      try {
        const responseText = response.content[0].text;
        // Extract JSON from response (Claude sometimes wraps in markdown code blocks)
        const jsonMatch = responseText.match(/\{[\s\S]*\}/);
        if (jsonMatch) {
          aiResult = JSON.parse(jsonMatch[0]);
        } else {
          throw new Error('No JSON found in response');
        }
      } catch (parseError) {
        console.error('Failed to parse AI response:', parseError);
        aiResult = {
          suggestedReply: response.content[0].text,
          suggestedAction: { type: 'INFO_ONLY' },
          confidence: 0.5,
          reasoning: 'Could not parse structured response',
        };
      }

      // Step 3.5: Post-process CHANGE_PICKUP actions to include pickup place ID
      // The frontend needs the ID to call the Bokun API
      if (aiResult.suggestedAction?.type === 'CHANGE_PICKUP' && bookings.length > 0) {
        const pickupName = aiResult.suggestedAction?.params?.newPickupLocation;
        console.log(`📍 CHANGE_PICKUP action detected, pickup name: "${pickupName}"`);

        // Get the booking - use the first matched booking
        const booking = bookings[0];
        const productBooking = booking.productBookings?.[0];

        // CRITICAL: Get IDs from flat fields (AI cache format) first, then nested format (raw Bokun)
        // AI cache has productId, productBookingId as flat fields
        const correctBookingId = String(booking.id);
        const correctProductBookingId = booking.productBookingId || productBooking?.id || null;
        const productId = booking.productId ||
          productBooking?.product?.id ||
          productBooking?.productId ||
          null;

        console.log(`📋 Booking IDs: bookingId=${correctBookingId}, productBookingId=${correctProductBookingId}, productId=${productId}`);

        // Ensure params object exists
        if (!aiResult.suggestedAction.params) {
          aiResult.suggestedAction.params = {};
        }

        // Override booking ID with the correct one from our lookup
        aiResult.suggestedAction.bookingId = correctBookingId;

        // Add productBookingId to params (avoids needing search in updatePickupLocation)
        if (correctProductBookingId) {
          aiResult.suggestedAction.params.productBookingId = correctProductBookingId;
          console.log(`✅ Added productBookingId ${correctProductBookingId} to action`);
        }

        // Lookup and add pickup place ID
        if (pickupName && productId) {
          console.log(`📍 Looking up pickup place for product ${productId}`);

          const pickupPlace = await findPickupPlaceId(productId, pickupName);
          if (pickupPlace) {
            aiResult.suggestedAction.params.pickupPlaceId = pickupPlace.id;
            aiResult.suggestedAction.params.pickupPlaceTitle = pickupPlace.title;
            console.log(`✅ Added pickup place ID ${pickupPlace.id} to action`);
          } else {
            console.log(`⚠️ Could not find pickup place ID for "${pickupName}"`);
            // Update the description to indicate manual change needed
            if (aiResult.suggestedAction.humanReadableDescription) {
              aiResult.suggestedAction.humanReadableDescription +=
                ' (Note: Pickup place ID not found - may need manual update)';
            }
          }
        } else if (!productId) {
          console.log(`⚠️ No product ID found in booking - cannot lookup pickup place`);
        }
      }

      // Step 4: Log the AI assist request for training
      await db.collection('ai_assist_logs').add({
        conversationId,
        customerEmail,
        customerName,
        bookingRefs: bookingRefs || [],
        matchedBookings: bookings.map(b => b.confirmationCode || b.id),
        messageContent: messageContent.substring(0, 500),
        suggestedReply: aiResult.suggestedReply,
        suggestedAction: aiResult.suggestedAction,
        confidence: aiResult.confidence,
        reasoning: aiResult.reasoning,
        status: 'pending', // Will be updated when staff acts on it
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdBy: request.auth.uid,
      });

      console.log('✅ AI Assist generated successfully');

      return {
        success: true,
        suggestedReply: aiResult.suggestedReply,
        suggestedAction: aiResult.suggestedAction,
        confidence: aiResult.confidence,
        reasoning: aiResult.reasoning,
        matchedBookings: bookings.map(b => ({
          id: b.id,
          confirmationCode: b.confirmationCode,
          customerName: b.customerFullName || b.customerName,
          productTitle: b.productTitle,
          startDate: b.startDate,
          status: b.status,
          pickupLocation: b.pickupPlaceName,
        })),
      };
    } catch (error) {
      console.error('❌ AI Assist error:', error);
      throw new Error(`AI Assist failed: ${error.message}`);
    }
  }
);

// Helper: Find bookings by customer email, name, or booking references
// Uses dedicated ai_booking_cache collection with all searchable fields
async function findCustomerBookings({ email, name, bookingRefs }) {
  const matchedBookings = [];
  const foundIds = new Set();
  const accessKey = process.env.BOKUN_ACCESS_KEY;
  const secretKey = process.env.BOKUN_SECRET_KEY;

  console.log(`🔍 Searching for bookings - refs: ${bookingRefs.join(', ')}, name: ${name || 'N/A'}, email: ${email || 'N/A'}`);

  try {
    // Step 1: Check if we have a fresh AI booking cache (< 60 minutes old)
    let aiCacheBookings = [];
    const cacheDoc = await db.collection('ai_booking_cache').doc('current').get();

    if (cacheDoc.exists) {
      const cacheData = cacheDoc.data();
      const cachedAt = cacheData.cachedAt?.toDate?.() || new Date(0);
      const cacheAgeMinutes = (Date.now() - cachedAt.getTime()) / (1000 * 60);

      // Cache valid for 60 minutes (fetching ~2000 bookings is expensive)
      if (cacheAgeMinutes < 60 && cacheData.bookings) {
        aiCacheBookings = cacheData.bookings;
        console.log(`📋 Using AI cache (${cacheAgeMinutes.toFixed(1)} min old): ${aiCacheBookings.length} bookings`);
      } else {
        console.log(`⏰ AI cache stale (${cacheAgeMinutes.toFixed(1)} min old), will refresh`);
      }
    }

    // Step 2: If cache is empty/stale, fetch from Bokun and update cache
    if (aiCacheBookings.length === 0 && accessKey && secretKey) {
      console.log('🔄 Refreshing AI booking cache from Bokun API...');
      aiCacheBookings = await refreshAIBookingCache(accessKey, secretKey);
    }

    if (aiCacheBookings.length === 0) {
      console.log('⚠️ No bookings in AI cache');
      return [];
    }

    console.log(`📋 Searching ${aiCacheBookings.length} bookings in AI cache`);

    // Step 3: Search through cached bookings for matches
    for (const booking of aiCacheBookings) {
      if (foundIds.has(booking.id)) continue;

      const externalRef = booking.externalBookingReference || '';
      const confirmationCode = booking.confirmationCode || '';
      const bookingId = String(booking.id || '');
      const customerName = (booking.customerName || '').toLowerCase();
      const customerEmail = (booking.customerEmail || '').toLowerCase();
      const phone = booking.phone || '';

      // Try to match by booking references
      for (const ref of bookingRefs) {
        const numericRef = ref.replace(/\D/g, '');
        if (!numericRef || numericRef.length < 6) continue;

        // Match by external booking reference (e.g., "1341729451" from Viator)
        if (externalRef && externalRef.includes(numericRef)) {
          booking.matchConfidence = 'HIGH';
          booking.matchReason = `External ref match: ${externalRef}`;
          matchedBookings.push(booking);
          foundIds.add(booking.id);
          console.log(`✅ HIGH match by external ref: ${confirmationCode} (ext: ${externalRef})`);
          break;
        }

        // Match by confirmation code number (e.g., "79818040" from "VIA-79818040")
        const confirmationNumbers = confirmationCode.replace(/\D/g, '');
        if (confirmationNumbers && confirmationNumbers === numericRef) {
          booking.matchConfidence = 'HIGH';
          booking.matchReason = `Confirmation code match: ${confirmationCode}`;
          matchedBookings.push(booking);
          foundIds.add(booking.id);
          console.log(`✅ HIGH match by confirmation code: ${confirmationCode}`);
          break;
        }

        // Match by booking ID
        if (bookingId === numericRef) {
          booking.matchConfidence = 'HIGH';
          booking.matchReason = `Booking ID match: ${bookingId}`;
          matchedBookings.push(booking);
          foundIds.add(booking.id);
          console.log(`✅ HIGH match by ID: ${confirmationCode}`);
          break;
        }
      }
    }

    // Step 4: Try customer name matching if no matches yet
    if (name && matchedBookings.length === 0) {
      const searchName = name.toLowerCase().trim();
      console.log(`🔍 Trying name match: "${searchName}"`);

      for (const booking of aiCacheBookings) {
        if (foundIds.has(booking.id)) continue;

        const customerName = (booking.customerName || '').toLowerCase();
        if (customerName && customerName.includes(searchName)) {
          booking.matchConfidence = 'MEDIUM';
          booking.matchReason = `Name match: "${booking.customerName}"`;
          matchedBookings.push(booking);
          foundIds.add(booking.id);
          console.log(`👤 MEDIUM match by name: ${booking.confirmationCode} (${booking.customerName})`);
        }
      }
    }

    // Step 5: Try email matching as last resort (skip automated emails)
    if (email && matchedBookings.length === 0 && !email.includes('expmessaging') && !email.includes('viator')) {
      const searchEmail = email.toLowerCase();
      for (const booking of aiCacheBookings) {
        if (foundIds.has(booking.id)) continue;

        if (booking.customerEmail && booking.customerEmail.toLowerCase() === searchEmail) {
          booking.matchConfidence = 'MEDIUM';
          booking.matchReason = `Email match: ${email}`;
          matchedBookings.push(booking);
          foundIds.add(booking.id);
          console.log(`📧 MEDIUM match by email: ${booking.confirmationCode}`);
        }
      }
    }

  } catch (error) {
    console.log('⚠️ Error searching AI booking cache:', error.message);
  }

  console.log(`📋 Total matched bookings: ${matchedBookings.length}`);
  return matchedBookings;
}

// Helper: Refresh AI booking cache from Bokun API
// Fetches ALL bookings with pagination
async function refreshAIBookingCache(accessKey, secretKey) {
  try {
    const method = 'POST';
    const path = '/booking.json/booking-search';

    // Fetch bookings from -45 days to +60 days (reasonable range for customer inquiries)
    // Reduced from ±90 to avoid Firestore 1 MB document size limit
    const now = new Date();
    const startDate = new Date(now);
    startDate.setDate(startDate.getDate() - 45);
    const endDate = new Date(now);
    endDate.setDate(endDate.getDate() + 60);

    const startDateStr = startDate.toISOString().split('T')[0];
    const endDateStr = endDate.toISOString().split('T')[0];

    console.log(`🔄 Fetching bookings from Bokun: ${startDateStr} to ${endDateStr}`);

    // Paginate to get ALL bookings
    let allBookings = [];
    let offset = 0;
    const pageSize = 50; // Bokun limits to 50 per page
    let hasMore = true;
    let totalHits = 0;

    while (hasMore) {
      const bokunDate = new Date().toISOString().replace('T', ' ').substring(0, 19);
      const message = bokunDate + accessKey + method + path;
      const signature = crypto.createHmac('sha1', secretKey).update(message).digest('base64');

      const requestBody = JSON.stringify({
        productConfirmationDateRange: { from: startDateStr, to: endDateStr },
        offset: offset,
        limit: pageSize,
      });

      const pageResult = await new Promise((resolve) => {
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
                resolve({ items: result.items || [], totalHits: result.totalHits || 0 });
              } catch (e) {
                resolve({ items: [], totalHits: 0 });
              }
            } else {
              console.log(`Bokun API error: ${res.statusCode}`);
              resolve({ items: [], totalHits: 0 });
            }
          });
        });

        req.on('error', () => resolve({ items: [], totalHits: 0 }));
        req.write(requestBody);
        req.end();
      });

      const items = pageResult.items;
      allBookings = allBookings.concat(items);
      totalHits = pageResult.totalHits || allBookings.length;

      console.log(`📋 Fetched page ${Math.floor(offset / pageSize) + 1}: ${items.length} bookings (total: ${allBookings.length}/${totalHits})`);

      // Check if there are more pages - continue as long as we got items AND haven't reached total
      offset += pageSize;
      // FIX: Bokun may return fewer items than requested - continue if we got ANY items and haven't reached total
      hasMore = items.length > 0 && allBookings.length < totalHits;

      // Safety limit to stay within Firestore 1 MB document limit
      if (allBookings.length >= 2000) {
        console.log('⚠️ Reached 2000 bookings limit (Firestore size constraint), stopping');
        hasMore = false;
      }
    }

    console.log(`📋 Fetched ${allBookings.length} total bookings from Bokun`);

    // Transform to AI cache format with all searchable fields
    const aiCacheBookings = allBookings.map(b => ({
      id: b.id,
      confirmationCode: b.confirmationCode || '',
      externalBookingReference: b.externalBookingReference || '',
      customerName: b.customer?.fullName || `${b.customer?.firstName || ''} ${b.customer?.lastName || ''}`.trim(),
      customerEmail: b.customer?.email || '',
      phone: b.customer?.phoneNumber || b.customer?.phone || '',
      productTitle: b.productBookings?.[0]?.product?.title || 'Northern Lights Tour',
      productId: b.productBookings?.[0]?.product?.id || b.productBookings?.[0]?.productId || null,
      productBookingId: b.productBookings?.[0]?.id || null,
      startDate: b.productBookings?.[0]?.startDate || b.startDate,
      startTime: b.productBookings?.[0]?.startTime || '',
      totalParticipants: b.productBookings?.[0]?.totalParticipants || b.totalParticipants || 1,
      status: b.productBookings?.[0]?.status || b.status || 'CONFIRMED',
      pickupPlace: b.productBookings?.[0]?.fields?.pickupPlace?.title || '',
      pickupPlaceId: b.productBookings?.[0]?.fields?.pickupPlace?.id || null,
      // Payment: check multiple fields because Bokun is inconsistent
      fullyPaid: b.fullyPaid || false,
      totalPaid: b.totalPaid || 0,
      totalPrice: b.totalPrice || 0,
    }));

    // Save to Firestore
    await db.collection('ai_booking_cache').doc('current').set({
      bookings: aiCacheBookings,
      cachedAt: new Date(),
      count: aiCacheBookings.length,
      dateRange: { from: startDateStr, to: endDateStr },
    });

    console.log(`💾 Saved ${aiCacheBookings.length} bookings to AI cache`);
    return aiCacheBookings;

  } catch (error) {
    console.log('⚠️ Failed to refresh AI booking cache:', error.message);
    return [];
  }
}

// Helper: Search Bokun for booking by ID
async function searchBokunBookingById(bookingId, accessKey, secretKey) {
  const method = 'POST';
  const path = '/booking.json/booking-search';

  const now = new Date();
  const bokunDate = now.toISOString().replace('T', ' ').substring(0, 19);
  const message = bokunDate + accessKey + method + path;
  const signature = crypto.createHmac('sha1', secretKey).update(message).digest('base64');

  const requestBody = JSON.stringify({ bookingId: parseInt(bookingId) });

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
            if (result.items && result.items.length > 0) {
              resolve(result.items[0]);
            } else {
              resolve(null);
            }
          } catch (e) {
            reject(new Error('Failed to parse Bokun response'));
          }
        } else {
          reject(new Error(`Bokun API error: ${res.statusCode}`));
        }
      });
    });

    req.on('error', reject);
    req.write(requestBody);
    req.end();
  });
}

// Helper: Find pickup place ID by name/title
// Called when AI detects CHANGE_PICKUP intent to get the ID needed for API
async function findPickupPlaceId(productId, pickupPlaceName) {
  const accessKey = process.env.BOKUN_ACCESS_KEY;
  const secretKey = process.env.BOKUN_SECRET_KEY;

  if (!accessKey || !secretKey || !productId) {
    console.log('⚠️ Cannot lookup pickup place - missing credentials or productId');
    return null;
  }

  try {
    console.log(`🔍 Looking up pickup place: "${pickupPlaceName}" for product ${productId}`);

    const pickupPath = `/activity.json/${productId}/pickup-places`;
    const pickupDate = new Date().toISOString().replace('T', ' ').substring(0, 19);
    const pickupMessage = pickupDate + accessKey + 'GET' + pickupPath;
    const pickupSignature = crypto
      .createHmac('sha1', secretKey)
      .update(pickupMessage)
      .digest('base64');

    const pickupPlaces = await new Promise((resolve) => {
      const options = {
        hostname: 'api.bokun.io',
        path: pickupPath,
        method: 'GET',
        headers: {
          'X-Bokun-AccessKey': accessKey,
          'X-Bokun-Date': pickupDate,
          'X-Bokun-Signature': pickupSignature,
        },
      };

      const apiReq = https.request(options, (apiRes) => {
        let data = '';
        apiRes.on('data', (chunk) => { data += chunk; });
        apiRes.on('end', () => {
          if (apiRes.statusCode >= 200 && apiRes.statusCode < 300) {
            try {
              const parsed = JSON.parse(data);
              resolve(Array.isArray(parsed) ? parsed : parsed.pickupPlaces || parsed.pickupDropoffPlaces || []);
            } catch (e) {
              console.log('⚠️ Failed to parse pickup places response');
              resolve([]);
            }
          } else {
            console.log(`⚠️ Pickup places API returned ${apiRes.statusCode}`);
            resolve([]);
          }
        });
      });

      apiReq.on('error', (e) => {
        console.log(`⚠️ Pickup places API error: ${e.message}`);
        resolve([]);
      });
      apiReq.end();
    });

    console.log(`📍 Found ${pickupPlaces.length} pickup places for product`);

    // Normalize search - case insensitive, partial match
    const normalizedSearch = pickupPlaceName.toLowerCase().trim();

    // Try exact match first
    let match = pickupPlaces.find(place => {
      const title = (place.title || place.name || '').toLowerCase();
      return title === normalizedSearch;
    });

    // Then try partial match
    if (!match) {
      match = pickupPlaces.find(place => {
        const title = (place.title || place.name || '').toLowerCase();
        return title.includes(normalizedSearch) || normalizedSearch.includes(title);
      });
    }

    // Try matching by address if still not found
    if (!match) {
      match = pickupPlaces.find(place => {
        const address = (place.address?.streetAddress || place.address || '').toLowerCase();
        return address.includes(normalizedSearch);
      });
    }

    if (match) {
      console.log(`✅ Found pickup place: ${match.title || match.name} (ID: ${match.id})`);
      return {
        id: match.id,
        title: match.title || match.name,
        address: match.address?.streetAddress || match.address || '',
      };
    }

    console.log(`⚠️ No pickup place found matching: "${pickupPlaceName}"`);
    console.log(`   Available places: ${pickupPlaces.slice(0, 10).map(p => p.title || p.name).join(', ')}...`);
    return null;

  } catch (error) {
    console.error(`❌ Error finding pickup place: ${error.message}`);
    return null;
  }
}

// Helper: Search Bokun for booking by confirmation code text (for external refs like Viator)
// This searches the confirmationCode field which includes external booking refs
async function searchBokunByConfirmationCode(searchText, accessKey, secretKey) {
  const method = 'POST';
  const path = '/booking.json/booking-search';

  const now = new Date();
  const bokunDate = now.toISOString().replace('T', ' ').substring(0, 19);
  const message = bokunDate + accessKey + method + path;
  const signature = crypto.createHmac('sha1', secretKey).update(message).digest('base64');

  // Search by confirmation code text - this matches the external booking ref
  const requestBody = JSON.stringify({
    confirmationCode: searchText,
    limit: 10
  });

  console.log(`🔍 Searching Bokun by confirmation code: ${searchText}`);

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
            console.log(`🔍 Confirmation code search returned ${result.items?.length || 0} results`);
            if (result.items && result.items.length > 0) {
              // Return the first matching booking
              const match = result.items.find(b =>
                b.confirmationCode?.includes(searchText) ||
                b.externalBookingReference === searchText ||
                String(b.id) === searchText
              );
              resolve(match || result.items[0]);
            } else {
              resolve(null);
            }
          } catch (e) {
            console.log('Failed to parse Bokun confirmation code search response');
            resolve(null);
          }
        } else {
          console.log(`Bokun confirmation code search error: ${res.statusCode}`);
          resolve(null);
        }
      });
    });

    req.on('error', (err) => {
      console.log('Bokun confirmation code search request error:', err.message);
      resolve(null);
    });
    req.write(requestBody);
    req.end();
  });
}

// Helper: Search Bokun for all recent bookings (for external ref matching)
// Fetches bookings in the next 30 days without email filter
async function searchBokunRecentBookings(accessKey, secretKey) {
  const method = 'POST';
  const path = '/booking.json/booking-search';

  // Search for all bookings in the next 30 days
  const now = new Date();
  const startDate = new Date(now);
  startDate.setDate(startDate.getDate() - 7); // Include 7 days in the past too
  const endDate = new Date(now);
  endDate.setDate(endDate.getDate() + 30);

  const startDateStr = startDate.toISOString().split('T')[0];
  const endDateStr = endDate.toISOString().split('T')[0];

  const bokunDate = now.toISOString().replace('T', ' ').substring(0, 19);
  const message = bokunDate + accessKey + method + path;
  const signature = crypto.createHmac('sha1', secretKey).update(message).digest('base64');

  const requestBody = JSON.stringify({
    productConfirmationDateRange: {
      from: startDateStr,
      to: endDateStr,
    },
    limit: 100, // Get more bookings to search through
  });

  console.log(`🔍 Searching ALL recent bookings from ${startDateStr} to ${endDateStr}`);

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
            console.log(`📋 Recent bookings search returned ${result.items?.length || 0} bookings`);
            resolve(result.items || []);
          } catch (e) {
            console.log('Failed to parse Bokun recent bookings response');
            resolve([]);
          }
        } else {
          console.log(`Bokun recent bookings search error: ${res.statusCode}`);
          resolve([]);
        }
      });
    });

    req.on('error', (err) => {
      console.log('Bokun recent bookings request error:', err.message);
      resolve([]);
    });
    req.write(requestBody);
    req.end();
  });
}

// Helper: Search Bokun for bookings by customer email
async function searchBokunBookingsByEmail(email, accessKey, secretKey) {
  const method = 'POST';
  const path = '/booking.json/booking-search';

  // Search for bookings in the next 30 days (most relevant)
  const now = new Date();
  const endDate = new Date(now);
  endDate.setDate(endDate.getDate() + 30);

  const startDateStr = now.toISOString().split('T')[0];
  const endDateStr = endDate.toISOString().split('T')[0];

  const bokunDate = now.toISOString().replace('T', ' ').substring(0, 19);
  const message = bokunDate + accessKey + method + path;
  const signature = crypto.createHmac('sha1', secretKey).update(message).digest('base64');

  const requestBody = JSON.stringify({
    productConfirmationDateRange: {
      from: startDateStr,
      to: endDateStr,
    },
    customerEmail: email,
    limit: 10,
  });

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
            reject(new Error('Failed to parse Bokun response'));
          }
        } else {
          resolve([]); // Return empty if search fails
        }
      });
    });

    req.on('error', () => resolve([]));
    req.write(requestBody);
    req.end();
  });
}

// Helper: Build booking context string for AI
function buildBookingContext(bookings) {
  if (bookings.length === 0) {
    return 'BOOKING CONTEXT:\nNo bookings found for this customer.';
  }

  let context = 'BOOKING CONTEXT:\n';
  bookings.forEach((booking, index) => {
    // Extract product booking details if available
    // Note: AI cache has flat fields (pickupPlace, productId), raw Bokun has nested productBookings
    const productBooking = booking.productBookings?.[0];
    const startDate = booking.startDate || productBooking?.startDate || 'Unknown';
    const startTime = booking.startTime || productBooking?.startTime || booking.pickupTime || null;
    // Check flat pickupPlace field first (AI cache), then nested
    const pickupPlace = booking.pickupPlace ||
      productBooking?.fields?.pickupPlace?.title ||
      booking.pickupPlaceName ||
      'Not assigned yet';
    const pickupPlaceId = booking.pickupPlaceId || productBooking?.fields?.pickupPlace?.id || null;
    const customerEmail = booking.customerEmail || booking.customer?.email || 'Unknown';

    // Extract product ID for pickup place lookups - check flat fields first
    const productId = booking.productId || productBooking?.product?.id || productBooking?.productId || null;
    const productBookingId = booking.productBookingId || productBooking?.id || null;

    context += `
Booking ${index + 1}${booking.matchConfidence ? ` [${booking.matchConfidence} CONFIDENCE MATCH]` : ''}:
- Confirmation Code: ${booking.confirmationCode || booking.id}
- Booking ID: ${booking.id}
- Product Booking ID: ${productBookingId || 'N/A'}
- Product ID: ${productId || 'N/A'}
- External Ref: ${booking.externalBookingReference || 'N/A'}
- Customer: ${booking.customer?.fullName || booking.customerFullName || booking.customerName || 'Unknown'}
- Email: ${customerEmail}
- Product: ${productBooking?.product?.title || booking.productTitle || 'Northern Lights Tour'}
- Tour Date: ${startDate}
- Departure/Pickup Time: ${startTime || 'See pickup details'}
- Pickup Location: ${pickupPlace}${pickupPlaceId ? ` (ID: ${pickupPlaceId})` : ''}
- Guests: ${booking.totalParticipants || booking.numberOfGuests || 1}
- Status: ${booking.status || 'CONFIRMED'}
${booking.matchReason ? `- Match Reason: ${booking.matchReason}` : ''}
`;
  });

  return context;
}


// ============================================
// AURORA ADVISOR EXPORTS
// ============================================
const auroraAdvisor = require('./aurora_advisor');
const auroraLearning = require('./aurora_learning_pipeline');

// Aurora Advisor
exports.getAuroraAdvisorRecommendation = auroraAdvisor.getAuroraAdvisorRecommendation;
exports.getQuickAuroraAssessment = auroraAdvisor.getQuickAuroraAssessment;

// Learning Pipeline
exports.runLearningPipeline = auroraLearning.runLearningPipeline;
exports.triggerLearningPipeline = auroraLearning.triggerLearningPipeline;
exports.createSightingFromShiftReport = auroraLearning.createSightingFromShiftReport;
exports.getLearningsContext = auroraLearning.getLearningsContext;

