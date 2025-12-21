const {onRequest} = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const crypto = require('crypto');
const https = require('https');

admin.initializeApp();

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

