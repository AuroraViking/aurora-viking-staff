/**
 * Bokun API Proxy Module
 * Handles proxied API calls to Bokun (keeps API keys server-side)
 */
const { onRequest } = require('firebase-functions/v2/https');
const crypto = require('crypto');
const https = require('https');
const { admin } = require('../utils/firebase');

/**
 * Cloud Function to proxy Bokun API requests
 * Uses onRequest with CORS for web compatibility
 */
const getBookings = onRequest(
    {
        cors: true,
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

            // Get data from request body
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

            // Pagination: fetch all bookings in batches
            const pageSize = 50;
            let allBookings = [];
            let offset = 0;
            let totalHits = 0;
            let hasMore = true;
            const method = 'POST';
            const path = '/booking.json/booking-search';

            while (hasMore) {
                // Generate Bokun API signature
                const now = new Date();
                const bokunDate = now.toISOString().replace('T', ' ').substring(0, 19);
                const message = bokunDate + accessKey + method + path;
                const signature = crypto
                    .createHmac('sha1', secretKey)
                    .update(message)
                    .digest('base64');

                // Prepare request body with pagination
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

                    const options = {
                        hostname: 'api.bokun.io',
                        path: path,
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

                // Accumulate results
                const items = result.items || [];
                allBookings = allBookings.concat(items);
                totalHits = result.totalHits || allBookings.length;

                console.log(`Fetched page ${Math.floor(offset / pageSize) + 1}: ${items.length} bookings (total so far: ${allBookings.length}/${totalHits})`);

                // Check if there are more pages
                offset += pageSize;
                hasMore = items.length === pageSize && allBookings.length < totalHits;

                // Safety limit
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

module.exports = {
    getBookings,
};
