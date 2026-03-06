// ============================================================
// CLOUD FUNCTION: disruptDeparture
// ============================================================
// Disrupts today's departure(s) on Bokun via /closeouts/toggle
//
// Endpoint: POST /closeouts/toggle
// Body: { activityIds: [728888], closed: true, date: "YYYY-MM-DD", startTimeIds: [2434679] }
// ============================================================

const { onCall } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const https = require('https');
const crypto = require('crypto');

const db = admin.firestore();

/**
 * Disrupt today's departure(s) on Bokun
 * Closes the departure so no new bookings can be made.
 * 
 * Uses the Bokun extranet endpoint: POST /closeouts/toggle
 * Payload: { activityIds: [id], closed: true, date: "YYYY-MM-DD", startTimeIds: [id] }
 */
const disruptDeparture = onCall(
    {
        region: 'us-central1',
        secrets: ['BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY'],
        timeoutSeconds: 60,
    },
    async (request) => {
        console.log('🚫 Disrupting departure...');

        if (!request.auth) {
            throw new Error('You must be logged in to disrupt departures');
        }

        const uid = request.auth.uid;
        const { date } = request.data || {};

        // Default to today (Iceland time)
        const now = new Date();
        const icelandDate = new Date(now.toLocaleString('en-US', { timeZone: 'Atlantic/Reykjavik' }));
        const dateString = date || `${icelandDate.getFullYear()}-${String(icelandDate.getMonth() + 1).padStart(2, '0')}-${String(icelandDate.getDate()).padStart(2, '0')}`;

        console.log(`📅 Disrupting departures for: ${dateString}`);

        const accessKey = process.env.BOKUN_ACCESS_KEY;
        const secretKey = process.env.BOKUN_SECRET_KEY;

        if (!accessKey || !secretKey) {
            throw new Error('Bokun API keys not configured');
        }

        try {
            // Get product config (activity IDs and their start time IDs)
            const products = await getProductConfig(dateString, accessKey, secretKey);
            console.log(`📋 Products to disrupt: ${JSON.stringify(products)}`);

            if (products.length === 0) {
                return {
                    success: true,
                    date: dateString,
                    message: 'No products configured for disruption',
                    disrupted: 0,
                };
            }

            // Build the closeout toggle request
            // All activity IDs and start time IDs go in one request
            const allActivityIds = [...new Set(products.map(p => p.activityId))];
            const allStartTimeIds = [...new Set(products.flatMap(p => p.startTimeIds))];

            console.log(`🚫 Closing out: activityIds=${JSON.stringify(allActivityIds)}, startTimeIds=${JSON.stringify(allStartTimeIds)}`);

            const result = await toggleCloseout({
                activityIds: allActivityIds,
                closed: true,
                date: dateString,
                startTimeIds: allStartTimeIds,
            }, accessKey, secretKey);

            // Log the action
            await db.collection('departure_disruptions').add({
                date: dateString,
                performedBy: uid,
                performedAt: admin.firestore.FieldValue.serverTimestamp(),
                activityIds: allActivityIds,
                startTimeIds: allStartTimeIds,
                result,
                success: true,
            });

            console.log(`✅ Departure disruption complete for ${dateString}`);

            return {
                success: true,
                date: dateString,
                activityIds: allActivityIds,
                startTimeIds: allStartTimeIds,
                disrupted: allStartTimeIds.length,
            };

        } catch (error) {
            console.error('❌ Error in disruptDeparture:', error);

            // Log failed attempt
            await db.collection('departure_disruptions').add({
                date: dateString,
                performedBy: uid,
                performedAt: admin.firestore.FieldValue.serverTimestamp(),
                success: false,
                error: error.message,
            });

            throw new Error(`Failed to disrupt departure: ${error.message}`);
        }
    }
);

/**
 * Get product configuration for disruption.
 * 
 * Tries to read from Firestore config first, falls back to 
 * fetching availabilities from Bokun to get startTimeIds.
 * 
 * Firestore doc: config/disruption_products
 * Format: {
 *   products: [
 *     { activityId: 728888, startTimeIds: [2434679] }
 *   ]
 * }
 */
async function getProductConfig(dateString, accessKey, secretKey) {
    // Try Firestore config first (fastest, most reliable)
    try {
        const configDoc = await db.collection('config').doc('disruption_products').get();
        if (configDoc.exists && configDoc.data().products) {
            console.log('📋 Using product config from Firestore');
            return configDoc.data().products;
        }
    } catch (e) {
        console.log('No disruption config found, trying availability lookup...');
    }

    // Fallback: look up availabilities to find startTimeIds
    const defaultActivityId = 728888; // Northern Lights tour

    try {
        const availabilities = await getAvailabilitiesForDate(
            defaultActivityId, dateString, accessKey, secretKey
        );

        if (availabilities && availabilities.length > 0) {
            const startTimeIds = availabilities
                .map(a => a.startTimeId || a.id)
                .filter(id => id != null);

            if (startTimeIds.length > 0) {
                console.log(`📋 Found startTimeIds from availabilities: ${JSON.stringify(startTimeIds)}`);
                return [{ activityId: defaultActivityId, startTimeIds }];
            }
        }
    } catch (e) {
        console.log('Availability lookup failed:', e.message);
    }

    // Last resort: use hardcoded defaults
    console.log('⚠️ Using hardcoded default product config');
    return [{ activityId: 728888, startTimeIds: [2434679] }];
}

/**
 * Call Bokun's closeout toggle endpoint
 * 
 * POST /closeouts/toggle
 * { activityIds: [728888], closed: true, date: "2026-04-27", startTimeIds: [2434679] }
 * 
 * We try api.bokun.io with HMAC first (like /booking.json/edit works).
 * If that fails, we try the extranet domain.
 */
async function toggleCloseout(payload, accessKey, secretKey) {
    const path = '/closeouts/toggle';
    const body = JSON.stringify(payload);

    console.log(`🚫 Closeout toggle: ${body}`);

    // Try api.bokun.io with HMAC auth first
    try {
        const result = await makeBokunRequest('api.bokun.io', 'POST', path, body, accessKey, secretKey);
        console.log('✅ Closeout via api.bokun.io succeeded');
        return { method: 'api_hmac', ...result };
    } catch (apiError) {
        console.log(`⚠️ api.bokun.io failed (${apiError.message}), trying extranet domain...`);
    }

    // Fallback: try extranet domain with HMAC
    try {
        const result = await makeBokunRequest('auroraviking.bokun.io', 'POST', path, body, accessKey, secretKey);
        console.log('✅ Closeout via extranet domain succeeded');
        return { method: 'extranet_hmac', ...result };
    } catch (extranetError) {
        console.error(`❌ Both endpoints failed.`);
        throw new Error(
            `Closeout toggle failed on both domains. ` +
            `This endpoint may require session-based auth (PLAY_SESSION cookie). ` +
            `Error: ${extranetError.message}`
        );
    }
}

/**
 * Make HMAC-signed request to a Bokun domain
 */
function makeBokunRequest(hostname, method, path, body, accessKey, secretKey) {
    const bokunDate = new Date().toISOString().replace('T', ' ').substring(0, 19);
    const message = bokunDate + accessKey + method + path;
    const signature = crypto.createHmac('sha1', secretKey).update(message).digest('base64');

    return new Promise((resolve, reject) => {
        const options = {
            hostname,
            path,
            method,
            headers: {
                'Content-Type': 'application/json;charset=UTF-8',
                'Content-Length': Buffer.byteLength(body),
                'X-Bokun-AccessKey': accessKey,
                'X-Bokun-Date': bokunDate,
                'X-Bokun-Signature': signature,
            },
        };

        const req = https.request(options, (res) => {
            let data = '';
            res.on('data', (chunk) => { data += chunk; });
            res.on('end', () => {
                console.log(`📡 ${hostname} ${method} ${path}: ${res.statusCode}`);
                if (res.statusCode >= 200 && res.statusCode < 300) {
                    // content-length: 0 means success with empty body (expected)
                    resolve({ statusCode: res.statusCode, body: data || 'OK' });
                } else {
                    reject(new Error(`${res.statusCode} - ${data.substring(0, 500)}`));
                }
            });
        });

        req.on('error', (e) => reject(e));
        req.write(body);
        req.end();
    });
}

/**
 * Get availabilities for a product on a specific date
 * Used as fallback to discover startTimeIds dynamically
 */
function getAvailabilitiesForDate(productId, dateString, accessKey, secretKey) {
    const path = `/activity.json/${productId}/availabilities`;
    const body = JSON.stringify({ start: dateString, end: dateString });

    const bokunDate = new Date().toISOString().replace('T', ' ').substring(0, 19);
    const message = bokunDate + accessKey + 'POST' + path;
    const signature = crypto.createHmac('sha1', secretKey).update(message).digest('base64');

    return new Promise((resolve, reject) => {
        const options = {
            hostname: 'api.bokun.io',
            path,
            method: 'POST',
            headers: {
                'Content-Type': 'application/json;charset=UTF-8',
                'Content-Length': Buffer.byteLength(body),
                'X-Bokun-AccessKey': accessKey,
                'X-Bokun-Date': bokunDate,
                'X-Bokun-Signature': signature,
            },
        };

        const req = https.request(options, (res) => {
            let data = '';
            res.on('data', (chunk) => { data += chunk; });
            res.on('end', () => {
                if (res.statusCode >= 200 && res.statusCode < 300) {
                    try {
                        const parsed = JSON.parse(data);
                        resolve(Array.isArray(parsed) ? parsed : [parsed]);
                    } catch (e) { resolve([]); }
                } else {
                    console.log(`⚠️ Availability check: ${res.statusCode}`);
                    resolve([]);
                }
            });
        });

        req.on('error', (e) => reject(e));
        req.write(body);
        req.end();
    });
}

module.exports = {
    disruptDeparture,
};
