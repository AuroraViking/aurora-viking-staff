/**
 * Bokun API Client
 * Handles authenticated requests to the Bokun API
 */
const crypto = require('crypto');
const https = require('https');

/**
 * Make an authenticated request to the Bokun API
 * @param {string} method - HTTP method (GET, POST, etc.)
 * @param {string} path - API path (e.g., '/booking.json/123')
 * @param {object|null} body - Request body for POST/PUT
 * @param {string} accessKey - Bokun access key
 * @param {string} secretKey - Bokun secret key
 * @returns {Promise<object>} - API response
 */
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

    // Add Content-Length header for POST requests
    const postData = body ? JSON.stringify(body) : null;
    if (postData) {
        options.headers['Content-Length'] = Buffer.byteLength(postData);
    }

    return new Promise((resolve, reject) => {
        const apiReq = https.request(options, (apiRes) => {
            let data = '';

            console.log(`📡 Bokun API Response: ${apiRes.statusCode}`);

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

/**
 * Search Bokun for booking by ID
 */
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

/**
 * Search Bokun for booking by confirmation code text (for external refs like Viator)
 */
async function searchBokunByConfirmationCode(searchText, accessKey, secretKey) {
    const method = 'POST';
    const path = '/booking.json/booking-search';

    const now = new Date();
    const bokunDate = now.toISOString().replace('T', ' ').substring(0, 19);
    const message = bokunDate + accessKey + method + path;
    const signature = crypto.createHmac('sha1', secretKey).update(message).digest('base64');

    const requestBody = JSON.stringify({
        confirmationCode: searchText,
        limit: 10
    });

    console.log(`🔍 Searching Bokun by confirmation code: ${searchText}`);

    return new Promise((resolve) => {
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

/**
 * Search Bokun for bookings by customer email
 */
async function searchBokunBookingsByEmail(email, accessKey, secretKey) {
    const method = 'POST';
    const path = '/booking.json/booking-search';

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

    return new Promise((resolve) => {
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
                        resolve([]);
                    }
                } else {
                    resolve([]);
                }
            });
        });

        req.on('error', () => resolve([]));
        req.write(requestBody);
        req.end();
    });
}

module.exports = {
    makeBokunRequest,
    searchBokunBookingById,
    searchBokunByConfirmationCode,
    searchBokunBookingsByEmail,
};
