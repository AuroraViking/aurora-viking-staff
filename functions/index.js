const {onRequest} = require('firebase-functions/v2/https');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {onCall} = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
// Use v1 functions for Firestore triggers
const functionsV1 = require('firebase-functions');
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

// ============================================
// FORMAT AND POPULATE THE SHEET
// ============================================
async function populateSheet(auth, spreadsheetId, reportData) {
  const sheets = google.sheets({version: 'v4', auth});
  
  // Prepare the data rows
  const rows = [];
  
  // Title row
  rows.push([`Aurora Viking Tour Report - ${reportData.date}`]);
  rows.push([`Generated: ${new Date().toLocaleString('en-GB', {timeZone: 'Atlantic/Reykjavik'})}`]);
  rows.push([`Total Guides: ${reportData.totalGuides} | Total Passengers: ${reportData.totalPassengers}`]);
  rows.push([]); // Empty row
  
  // Process each guide
  reportData.guides.forEach((guide) => {
    // Guide header
    rows.push([
      `🚌 ${guide.guideName}`,
      '',
      '',
      `Total: ${guide.totalPassengers} passengers`,
    ]);
    
    // Column headers for this guide's bookings
    rows.push([
      'Customer Name',
      'Passengers',
      'Pickup Location', 
      'Pickup Time',
      'Phone',
      'Email',
    ]);
    
    // Booking rows
    guide.bookings.forEach((booking) => {
      rows.push([
        booking.customerName || 'Unknown',
        booking.participants || 0,
        booking.pickupLocation || 'Unknown',
        booking.pickupTime || '',
        booking.phone || '',
        booking.email || '',
      ]);
    });
    
    // Empty rows between guides
    rows.push([]);
    rows.push([]);
  });
  
  // Write all data to the sheet
  await sheets.spreadsheets.values.update({
    spreadsheetId,
    range: 'Sheet1!A1',
    valueInputOption: 'USER_ENTERED',
    requestBody: {
      values: rows,
    },
  });
  
  // Apply formatting
  const requests = [
    // Bold the title row
    {
      repeatCell: {
        range: {sheetId: 0, startRowIndex: 0, endRowIndex: 1},
        cell: {
          userEnteredFormat: {
            textFormat: {bold: true, fontSize: 16},
          },
        },
        fields: 'userEnteredFormat.textFormat',
      },
    },
    // Bold the summary row
    {
      repeatCell: {
        range: {sheetId: 0, startRowIndex: 2, endRowIndex: 3},
        cell: {
          userEnteredFormat: {
            textFormat: {bold: true},
          },
        },
        fields: 'userEnteredFormat.textFormat',
      },
    },
    // Set column widths
    {
      updateDimensionProperties: {
        range: {
          sheetId: 0,
          dimension: 'COLUMNS',
          startIndex: 0,
          endIndex: 1,
        },
        properties: {pixelSize: 200},
        fields: 'pixelSize',
      },
    },
    {
      updateDimensionProperties: {
        range: {
          sheetId: 0,
          dimension: 'COLUMNS',
          startIndex: 2,
          endIndex: 3,
        },
        properties: {pixelSize: 200},
        fields: 'pixelSize',
      },
    },
  ];
  
  // Find and format guide header rows (the ones with 🚌)
  let currentRow = 4; // Start after the header rows
  reportData.guides.forEach((guide) => {
    // Bold the guide name row
    requests.push({
      repeatCell: {
        range: {sheetId: 0, startRowIndex: currentRow, endRowIndex: currentRow + 1},
        cell: {
          userEnteredFormat: {
            textFormat: {bold: true, fontSize: 12},
            backgroundColor: {red: 0.9, green: 0.95, blue: 1.0},
          },
        },
        fields: 'userEnteredFormat.textFormat,userEnteredFormat.backgroundColor',
      },
    });
    
    // Bold the column headers
    requests.push({
      repeatCell: {
        range: {sheetId: 0, startRowIndex: currentRow + 1, endRowIndex: currentRow + 2},
        cell: {
          userEnteredFormat: {
            textFormat: {bold: true},
            backgroundColor: {red: 0.95, green: 0.95, blue: 0.95},
          },
        },
        fields: 'userEnteredFormat.textFormat,userEnteredFormat.backgroundColor',
      },
    });
    
    currentRow += guide.bookings.length + 4; // bookings + header rows + empty rows
  });
  
  await sheets.spreadsheets.batchUpdate({
    spreadsheetId,
    requestBody: {requests},
  });
  
  console.log('✨ Sheet formatted successfully');
}

// ============================================
// MAIN REPORT GENERATION LOGIC
// ============================================
async function generateReport(targetDate) {
  console.log(`📅 Generating report for: ${targetDate}`);
  
  // Fetch pickup assignments for the date
  const assignmentsSnapshot = await db
    .collection('pickup_assignments')
    .where('date', '==', targetDate)
    .get();
  
  if (assignmentsSnapshot.empty) {
    console.log('⚠️ No pickup assignments found for this date.');
    return {success: false, message: 'No assignments found', date: targetDate};
  }
  
  // Group bookings by guide
  const guideData = {};
  const individualAssignments = [];
  
  assignmentsSnapshot.forEach((doc) => {
    const data = doc.data();
    
    if (data.bookingId) {
      // Individual assignment format
      individualAssignments.push({
        bookingId: data.bookingId,
        guideId: data.guideId,
        guideName: data.guideName,
        date: data.date,
      });
    } else if (data.bookings) {
      // Bulk assignment format
      if (!guideData[data.guideId]) {
        guideData[data.guideId] = {
          guideName: data.guideName,
          totalPassengers: 0,
          bookings: [],
        };
      }
      guideData[data.guideId].totalPassengers += data.totalPassengers || 0;
      guideData[data.guideId].bookings.push(...(data.bookings || []));
    }
  });
  
  // If we have individual assignments, fetch booking details from cache
  if (Object.keys(guideData).length === 0 && individualAssignments.length > 0) {
    console.log(`📋 Processing ${individualAssignments.length} individual assignments`);
    
    const cacheDoc = await db.collection('cached_bookings').doc(targetDate).get();
    const cachedBookings = cacheDoc.exists ? (cacheDoc.data().bookings || []) : [];
    
    const bookingMap = {};
    cachedBookings.forEach((booking) => {
      bookingMap[booking.id] = booking;
    });
    
    individualAssignments.forEach((assignment) => {
      if (!guideData[assignment.guideId]) {
        guideData[assignment.guideId] = {
          guideName: assignment.guideName,
          totalPassengers: 0,
          bookings: [],
        };
      }
      
      const booking = bookingMap[assignment.bookingId];
      if (booking) {
        guideData[assignment.guideId].bookings.push(booking);
        guideData[assignment.guideId].totalPassengers += booking.totalParticipants || 0;
      }
    });
  }
  
  console.log(`👥 Found ${Object.keys(guideData).length} guides with assignments`);
  
  // Build report data
  const reportData = {
    date: targetDate,
    generatedAt: new Date().toISOString(),
    totalGuides: Object.keys(guideData).length,
    totalPassengers: Object.values(guideData).reduce((sum, g) => sum + g.totalPassengers, 0),
    guides: Object.entries(guideData).map(([guideId, data]) => ({
      guideId,
      guideName: data.guideName,
      totalPassengers: data.totalPassengers,
      bookings: data.bookings.map((b) => ({
        id: b.id,
        customerName: b.customerFullName || b.customerName || 'Unknown',
        participants: b.totalParticipants || 0,
        pickupLocation: b.pickupPlaceName || 'Unknown',
        pickupTime: b.pickupTime || null,
        phone: b.customerPhone || '',
        email: b.customerEmail || '',
      })),
    })),
  };
  
  // Save to Firestore
  await db.collection('tour_reports').doc(targetDate).set(reportData);
  console.log(`✅ Report saved to Firestore: tour_reports/${targetDate}`);
  
  // Create Google Sheet
  try {
    const auth = await getGoogleAuth();
    const sheetTitle = `Aurora Viking Tour Report - ${targetDate}`;
    
    const spreadsheetId = await createSheetInFolder(auth, sheetTitle, DRIVE_FOLDER_ID);
    await populateSheet(auth, spreadsheetId, reportData);
    
    // Update Firestore with the sheet URL
    const sheetUrl = `https://docs.google.com/spreadsheets/d/${spreadsheetId}`;
    await db.collection('tour_reports').doc(targetDate).update({
      sheetUrl: sheetUrl,
      spreadsheetId: spreadsheetId,
    });
    
    console.log(`📊 Google Sheet created: ${sheetUrl}`);
    
    return {
      success: true,
      date: targetDate,
      guides: Object.keys(guideData).length,
      totalPassengers: reportData.totalPassengers,
      sheetUrl: sheetUrl,
    };
    
  } catch (sheetError) {
    console.error('⚠️ Failed to create Google Sheet:', sheetError);
    // Don't fail the whole function - Firestore save succeeded
    return {
      success: true,
      date: targetDate,
      guides: Object.keys(guideData).length,
      totalPassengers: reportData.totalPassengers,
      sheetError: sheetError.message,
    };
  }
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
// SCHEDULED FUNCTION - Runs at 11pm Iceland time
// ============================================
exports.generateTourReport = onSchedule(
  {
    schedule: '0 23 * * *',
    timeZone: 'Atlantic/Reykjavik',
    region: 'us-central1',
  },
  async () => {
    console.log('🚀 Starting scheduled tour report generation...');
    
    const today = new Date();
    // Adjust for Iceland timezone
    const icelandDate = new Date(today.toLocaleString('en-US', {timeZone: 'Atlantic/Reykjavik'}));
    const dateStr = `${icelandDate.getFullYear()}-${String(icelandDate.getMonth() + 1).padStart(2, '0')}-${String(icelandDate.getDate()).padStart(2, '0')}`;
    
    return await generateReport(dateStr);
  }
);

// ============================================
// MANUAL TRIGGER - Call from app or for testing
// ============================================
exports.generateTourReportManual = onCall(
  {
    region: 'us-central1',
    invoker: 'public',  // Allow public access for internal staff app
  },
  async (request) => {
    console.log('📝 Manual report generation requested');
    
    const dateParam = request.data?.date;
    
    // If no date provided, use today (Iceland time)
    let targetDate;
    if (dateParam) {
      targetDate = dateParam;
    } else {
      const today = new Date();
      const icelandDate = new Date(today.toLocaleString('en-US', {timeZone: 'Atlantic/Reykjavik'}));
      targetDate = `${icelandDate.getFullYear()}-${String(icelandDate.getMonth() + 1).padStart(2, '0')}-${String(icelandDate.getDate()).padStart(2, '0')}`;
    }
    
    return await generateReport(targetDate);
  }
);

// ============================================
// NOTIFICATION FUNCTIONS
// ============================================

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
 * Firestore trigger: Send notification when pickup is completed (isArrived becomes true)
 */
exports.onPickupCompleted = functionsV1.firestore
  .onDocumentWritten('booking_status/{documentId}', async (change, context) => {
    // Extract documentId from context or change
    const documentId = context?.params?.documentId || change.after?.ref?.id || change.before?.ref?.id;
    
    if (!documentId) {
      console.log('⚠️ Could not extract documentId from context or change');
      console.log('   context:', context);
      console.log('   change.after.ref:', change.after?.ref?.id);
      console.log('   change.before.ref:', change.before?.ref?.id);
      return;
    }
    
    console.log('🔔 onPickupCompleted triggered for document:', documentId);
    
    // Check if document was deleted
    if (!change.after.exists) {
      console.log('⚠️ Document was deleted, skipping');
      return;
    }

    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.data();
    
    console.log('📊 Before data:', JSON.stringify(before));
    console.log('📊 After data:', JSON.stringify(after));

    // Extract date and bookingId from document ID (format: YYYY-MM-DD_bookingId)
    const parts = documentId.split('_');
    console.log(`🔍 Parsing document ID: "${documentId}" -> parts: [${parts.join(', ')}]`);
    
    if (parts.length < 4) {
      console.log(`⚠️ Document ID doesn't have enough parts (need at least 4 for YYYY-MM-DD_bookingId), got ${parts.length}`);
      return;
    }
    const date = parts.slice(0, 3).join('-'); // YYYY-MM-DD
    const bookingId = parts.slice(3).join('_'); // bookingId (may contain underscores)
    console.log(`✅ Parsed: date="${date}", bookingId="${bookingId}"`);

    // Check if isArrived changed from false/undefined to true
    const wasArrived = before?.isArrived === true;
    const isNowArrived = after?.isArrived === true;
    
    console.log(`🔍 Checking pickup status: wasArrived=${wasArrived}, isNowArrived=${isNowArrived}`);

    if (!wasArrived && isNowArrived) {
      console.log(`✅ Pickup completed detected for booking ${bookingId} on ${date}`);

      // Get booking details
      const booking = await getBookingDetails(bookingId, date);
      const customerName = booking?.customerFullName || booking?.customerName || 'Unknown Customer';
      const pickupLocation = booking?.pickupPlaceName || 'Unknown Location';

      // Send notification to all users
      await sendNotificationToAdmins(
        '✅ Pickup Completed',
        `${customerName} has been picked up from ${pickupLocation}`,
        {
          type: 'pickup_completed',
          bookingId: bookingId,
          date: date,
          customerName: customerName,
          pickupLocation: pickupLocation,
        }
      );
    } else {
      console.log('ℹ️ Pickup status did not change from false to true, skipping notification');
    }
  });

/**
 * Firestore trigger: Send notification when no-show is marked
 */
exports.onNoShowMarked = functionsV1.firestore
  .onDocumentWritten('booking_status/{documentId}', async (change, context) => {
    // Extract documentId from context or change
    const documentId = context?.params?.documentId || change.after?.ref?.id || change.before?.ref?.id;
    
    if (!documentId) {
      console.log('⚠️ Could not extract documentId from context or change');
      console.log('   context:', context);
      console.log('   change.after.ref:', change.after?.ref?.id);
      console.log('   change.before.ref:', change.before?.ref?.id);
      return;
    }
    
    console.log('🔔 onNoShowMarked triggered for document:', documentId);
    
    // Check if document was deleted
    if (!change.after.exists) {
      console.log('⚠️ Document was deleted, skipping');
      return;
    }

    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.data();
    
    console.log('📊 Before data:', JSON.stringify(before));
    console.log('📊 After data:', JSON.stringify(after));

    // Extract date and bookingId from document ID
    const parts = documentId.split('_');
    console.log(`🔍 Parsing document ID: "${documentId}" -> parts: [${parts.join(', ')}]`);
    
    if (parts.length < 4) {
      console.log(`⚠️ Document ID doesn't have enough parts (need at least 4 for YYYY-MM-DD_bookingId), got ${parts.length}`);
      return;
    }
    const date = parts.slice(0, 3).join('-'); // YYYY-MM-DD
    const bookingId = parts.slice(3).join('_'); // bookingId
    console.log(`✅ Parsed: date="${date}", bookingId="${bookingId}"`);

    // Check if isNoShow changed from false/undefined to true
    const wasNoShow = before?.isNoShow === true;
    const isNowNoShow = after?.isNoShow === true;
    
    console.log(`🔍 Checking no-show status: wasNoShow=${wasNoShow}, isNowNoShow=${isNowNoShow}`);

    if (!wasNoShow && isNowNoShow) {
      console.log(`✅ No-show detected for booking ${bookingId} on ${date}`);

      // Get booking details
      const booking = await getBookingDetails(bookingId, date);
      const customerName = booking?.customerFullName || booking?.customerName || 'Unknown Customer';
      const pickupLocation = booking?.pickupPlaceName || 'Unknown Location';

      // Send notification to all users
      await sendNotificationToAdmins(
        '⚠️ No-Show Reported',
        `${customerName} did not show up at ${pickupLocation}`,
        {
          type: 'no_show',
          bookingId: bookingId,
          date: date,
          customerName: customerName,
          pickupLocation: pickupLocation,
        }
      );
    } else {
      console.log('ℹ️ No-show status did not change from false to true, skipping notification');
    }
  });

