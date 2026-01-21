/**
 * AI Assist Module
 * Handles AI-powered draft responses and booking context
 */
const { onCall } = require('firebase-functions/v2/https');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const crypto = require('crypto');
const https = require('https');
const { admin, db } = require('../utils/firebase');
const { AI_SYSTEM_PROMPT } = require('../config');

// ============================================
// HELPER FUNCTIONS
// ============================================

/**
 * Get booking context for AI prompt
 */
async function getBookingContextForAi(bookingNumbers) {
    if (!bookingNumbers || bookingNumbers.length === 0) {
        return null;
    }
    // TODO: Look up bookings in Firestore cache
    return null;
}

/**
 * Generate draft with Claude
 */
async function generateDraftWithClaude({ message, customer, bookingContext, conversationHistory }) {
    const Anthropic = require('@anthropic-ai/sdk').default;
    const anthropic = new Anthropic({
        apiKey: process.env.ANTHROPIC_API_KEY,
    });

    let prompt = `You are Aurora Viking Staff AI assistant. Generate a helpful, professional draft response.

Customer: ${customer?.name || 'Unknown'}
Email: ${customer?.email || 'Unknown'}

`;

    if (bookingContext) {
        prompt += `Booking Context:\n${bookingContext}\n\n`;
    }

    if (conversationHistory && conversationHistory.length > 0) {
        prompt += `Conversation History:\n`;
        for (const msg of conversationHistory) {
            const role = msg.direction === 'inbound' ? 'Customer' : 'Staff';
            prompt += `${role}: ${msg.content}\n\n`;
        }
    }

    prompt += `\nLatest Customer Message:\n${message}\n\nGenerate a draft response. Be helpful, professional, and friendly.`;

    const response = await anthropic.messages.create({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 1024,
        messages: [{ role: 'user', content: prompt }],
    });

    return {
        content: response.content[0].text,
        confidence: 0.8,
        tone: 'professional',
        reasoning: 'Generated based on message content and context',
    };
}

/**
 * Find customer bookings by email, name, or booking references
 * Uses dedicated ai_booking_cache collection with all searchable fields
 */
async function findCustomerBookings({ email, name, bookingRefs }) {
    const matchedBookings = [];
    const foundIds = new Set();
    const accessKey = process.env.BOKUN_ACCESS_KEY;
    const secretKey = process.env.BOKUN_SECRET_KEY;

    console.log(`🔍 Searching for bookings - refs: ${(bookingRefs || []).join(', ')}, name: ${name || 'N/A'}, email: ${email || 'N/A'}`);

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

            // Try to match by booking references
            for (const ref of (bookingRefs || [])) {
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

        // Step 5.5: If still no match and we have a name, search today's (and tomorrow's) bookings by name
        // This helps when customers email from different addresses after tour is OFF
        if (matchedBookings.length === 0 && name) {
            console.log(`📅 No match found, searching today's bookings by name: "${name}"`);
            const searchName = name.toLowerCase();

            // Get today's and tomorrow's date in Iceland timezone
            const now = new Date();
            const icelandNow = new Date(now.toLocaleString('en-US', { timeZone: 'Atlantic/Reykjavik' }));
            const todayStr = icelandNow.toISOString().split('T')[0];
            const tomorrow = new Date(icelandNow);
            tomorrow.setDate(tomorrow.getDate() + 1);
            const tomorrowStr = tomorrow.toISOString().split('T')[0];

            for (const booking of aiCacheBookings) {
                if (foundIds.has(booking.id)) continue;

                const bookingDate = booking.startDate || '';
                // Check if booking is for today or tomorrow
                if (bookingDate === todayStr || bookingDate === tomorrowStr) {
                    const customerName = (booking.customerName || '').toLowerCase();

                    // Check if name matches (partial match for flexibility)
                    if (customerName && (customerName.includes(searchName) || searchName.includes(customerName.split(' ')[0]))) {
                        booking.matchConfidence = 'MEDIUM';
                        booking.matchReason = `Name match in ${bookingDate === todayStr ? 'today' : 'tomorrow'}'s bookings: "${booking.customerName}"`;
                        matchedBookings.push(booking);
                        foundIds.add(booking.id);
                        console.log(`👤 MEDIUM match by name in ${bookingDate === todayStr ? 'today' : 'tomorrow'}'s bookings: ${booking.confirmationCode} (${booking.customerName})`);
                    }
                }
            }
        }

    } catch (error) {
        console.log('⚠️ Error searching AI booking cache:', error.message);
    }

    // Step 6: Enhance matched bookings with pickup data from booking_management_cache
    // This cache has better pickup info because it uses the getBookings API which returns pickupPlace correctly
    if (matchedBookings.length > 0) {
        console.log(`📍 Enhancing ${matchedBookings.length} bookings with pickup data from booking_management_cache...`);

        try {
            // Get recent booking_management_cache documents
            const today = new Date();
            const startDate = new Date(today);
            startDate.setDate(startDate.getDate() - 7); // Look back 7 days
            const endDate = new Date(today);
            endDate.setDate(endDate.getDate() + 30); // Look forward 30 days

            // Try to find cache documents for recent date ranges
            const cacheSnapshot = await db.collection('booking_management_cache')
                .limit(10) // Get up to 10 cache documents
                .get();

            const pickupLookup = new Map(); // bookingId -> pickup info

            for (const doc of cacheSnapshot.docs) {
                const data = doc.data();
                const bookings = data.bookings || [];

                for (const b of bookings) {
                    const bookingId = String(b.id || b.bookingId || '');
                    const pickup = b.pickupLocation || b.pickupPlaceName || '';
                    const pickupTime = b.pickupTime || '';

                    if (bookingId && pickup) {
                        pickupLookup.set(bookingId, { location: pickup, time: pickupTime });
                    }
                }
            }

            console.log(`📍 Found pickup data for ${pickupLookup.size} bookings in cache`);

            // Enhance matched bookings with pickup info
            for (const booking of matchedBookings) {
                const bookingId = String(booking.id);
                const cachedPickup = pickupLookup.get(bookingId);

                if (cachedPickup && cachedPickup.location) {
                    console.log(`✅ Enhanced booking ${booking.confirmationCode} with pickup: ${cachedPickup.location}`);
                    booking.pickupPlace = cachedPickup.location;
                    booking.pickupPlaceName = cachedPickup.location;
                    if (cachedPickup.time) {
                        booking.pickupTime = cachedPickup.time;
                    }
                }
            }
        } catch (enhanceError) {
            console.log(`⚠️ Could not enhance with pickup data: ${enhanceError.message}`);
        }

        // Step 7: If pickup still missing, fetch directly from Bokun API
        const accessKey = process.env.BOKUN_ACCESS_KEY;
        const secretKey = process.env.BOKUN_SECRET_KEY;

        for (const booking of matchedBookings) {
            if (!booking.pickupPlace || booking.pickupPlace === 'Not assigned yet') {
                console.log(`📍 Pickup missing for ${booking.confirmationCode}, fetching from Bokun API...`);

                try {
                    const fullBooking = await searchBokunBookingById(booking.id, accessKey, secretKey);
                    if (fullBooking) {
                        const productBooking = fullBooking.productBookings?.[0];
                        const pickup = productBooking?.pickupPlace?.title ||
                            productBooking?.pickupPlace?.name ||
                            productBooking?.fields?.pickupPlace?.title ||
                            productBooking?.fields?.pickupPlaceDescription ||
                            null;

                        if (pickup) {
                            console.log(`✅ Found pickup from API: ${pickup}`);
                            booking.pickupPlace = pickup;
                            booking.pickupPlaceName = pickup;
                            booking.pickupPlaceId = productBooking?.pickupPlace?.id ||
                                productBooking?.fields?.pickupPlace?.id || null;
                        } else {
                            console.log(`⚠️ No pickup found in Bokun API response`);
                        }
                    }
                } catch (apiError) {
                    console.log(`⚠️ Could not fetch from Bokun: ${apiError.message}`);
                }
            }
        }
    }

    console.log(`📋 Total matched bookings: ${matchedBookings.length}`);
    return matchedBookings;
}

/**
 * Refresh AI booking cache from Bokun API - fetches ALL bookings with pagination
 */
async function refreshAIBookingCache(accessKey, secretKey) {
    try {
        const method = 'POST';
        const path = '/booking.json/booking-search';

        // Fetch bookings from -45 days to +60 days
        const now = new Date();
        const startDate = new Date(now);
        startDate.setDate(startDate.getDate() - 45);
        const endDate = new Date(now);
        endDate.setDate(endDate.getDate() + 60);

        const startDateStr = startDate.toISOString().split('T')[0];
        const endDateStr = endDate.toISOString().split('T')[0];

        console.log(`🔄 Fetching bookings from Bokun: ${startDateStr} to ${endDateStr}`);

        let allBookings = [];
        let offset = 0;
        const pageSize = 50;
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

            offset += pageSize;
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
            // Check multiple locations for pickup place - Bokun stores it in different places
            pickupPlace: b.productBookings?.[0]?.pickupPlace?.title ||
                b.productBookings?.[0]?.pickupPlace?.name ||
                b.productBookings?.[0]?.fields?.pickupPlace?.title ||
                b.productBookings?.[0]?.fields?.pickupPlaceDescription ||
                b.productBookings?.[0]?.pickup?.title ||
                b.productBookings?.[0]?.pickup?.name ||
                '',
            pickupPlaceId: b.productBookings?.[0]?.pickupPlace?.id ||
                b.productBookings?.[0]?.fields?.pickupPlace?.id ||
                b.productBookings?.[0]?.pickup?.id ||
                null,
            fullyPaid: b.fullyPaid || false,
            totalPaid: b.totalPaid || 0,
            totalPrice: b.totalPrice || 0,
            // Store raw fields for debugging
            rawPickupFields: JSON.stringify(b.productBookings?.[0]?.fields || {}),
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
        productConfirmationDateRange: { from: startDateStr, to: endDateStr },
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

/**
 * Find pickup place ID by name/title
 */
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
        const pickupSignature = crypto.createHmac('sha1', secretKey).update(pickupMessage).digest('base64');

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
                            resolve([]);
                        }
                    } else {
                        resolve([]);
                    }
                });
            });

            apiReq.on('error', () => resolve([]));
            apiReq.end();
        });

        console.log(`📍 Found ${pickupPlaces.length} pickup places for product`);

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
        return null;

    } catch (error) {
        console.error(`❌ Error finding pickup place: ${error.message}`);
        return null;
    }
}

/**
 * Build booking context string for AI
 */
function buildBookingContext(bookings) {
    if (bookings.length === 0) {
        return 'BOOKING CONTEXT:\nNo bookings found for this customer.';
    }

    let context = 'BOOKING CONTEXT:\n';
    bookings.forEach((booking, index) => {
        const productBooking = booking.productBookings?.[0];
        const startDate = booking.startDate || productBooking?.startDate || 'Unknown';
        const startTime = booking.startTime || productBooking?.startTime || booking.pickupTime || null;

        // Check multiple locations for pickup - Bokun stores it differently depending on source
        const pickupPlace = booking.pickupPlace ||
            productBooking?.pickupPlace?.title ||
            productBooking?.pickupPlace?.name ||
            productBooking?.fields?.pickupPlace?.title ||
            productBooking?.fields?.pickupPlaceDescription ||
            productBooking?.pickup?.title ||
            productBooking?.pickup?.name ||
            booking.pickupPlaceName ||
            'Not assigned yet';

        const pickupPlaceId = booking.pickupPlaceId ||
            productBooking?.pickupPlace?.id ||
            productBooking?.fields?.pickupPlace?.id ||
            productBooking?.pickup?.id ||
            null;

        const customerEmail = booking.customerEmail || booking.customer?.email || 'Unknown';
        const productId = booking.productId || productBooking?.product?.id || productBooking?.productId || null;
        const productBookingId = booking.productBookingId || productBooking?.id || null;

        // Log pickup info for debugging
        console.log(`📍 Booking ${booking.confirmationCode || booking.id} pickup: "${pickupPlace}" (ID: ${pickupPlaceId})`);

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
// CLOUD FUNCTIONS
// ============================================

/**
 * Generate AI draft response when new inbound message is created
 * DEPRECATED: Now using on-demand generateBookingAiAssist instead
 */
const generateAiDraft = onDocumentCreated(
    {
        document: 'messages/{messageId}',
        region: 'us-central1',
        secrets: ['ANTHROPIC_API_KEY'],
    },
    async (event) => {
        // DISABLED: Auto AI draft generation is disabled to save on API tokens
        console.log('⏭️ Auto AI draft generation is disabled. Use generateBookingAiAssist instead.');
        return null;
    }
);

/**
 * On-demand AI Booking Assist
 * Called when staff wants AI help for a specific message
 */
const generateBookingAiAssist = onCall(
    {
        region: 'us-central1',
        timeoutSeconds: 300, // 5 minute timeout for cache refresh + API calls
        memory: '1GiB', // Increase memory for large booking cache
        secrets: ['ANTHROPIC_API_KEY', 'BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY'],
    },
    async (request) => {
        console.log('🤖 AI Booking Assist requested');

        if (!request.auth) {
            throw new Error('You must be logged in to use AI Assist');
        }

        const { conversationId, messageContent, customerEmail, customerName, bookingRefs } = request.data;

        if (!conversationId || !messageContent) {
            throw new Error('conversationId and messageContent are required');
        }

        try {
            // Extract booking references from the message content
            const bookingPatterns = [
                /\b(?:AUR|VIA|GET|TDI|AV|aur|via|get|tdi|av)[-\s]?(\d{6,10})\b/gi,  // Prefixed booking refs
                /\b(?:booking|confirmation|reference|ref|order)[:\.\s#]*(\d{6,15})\b/gi,  // booking: 12345678
                /\b(\d{8,10})\b/g,  // 8-10 digit numbers (common booking ID length)
                /\b([A-Z0-9]{10,15})\b/g,  // Alphanumeric refs like GYGBLHXM9R2Y
            ];

            const extractedRefs = new Set(bookingRefs || []);
            for (const pattern of bookingPatterns) {
                const matches = messageContent.matchAll(pattern);
                for (const match of matches) {
                    const ref = match[1] || match[0];
                    const numericRef = ref.replace(/\D/g, '');
                    if (numericRef.length >= 6) {
                        extractedRefs.add(numericRef);
                        console.log(`🔍 Found booking reference in message: ${ref} -> ${numericRef}`);
                    }
                }
            }
            const allBookingRefs = Array.from(extractedRefs);
            console.log(`🔍 Total booking refs to search: ${allBookingRefs.join(', ') || 'none'}`);

            // Find related bookings
            console.log('📋 Looking up bookings for:', { customerEmail, customerName, bookingRefs: allBookingRefs });
            const bookings = await findCustomerBookings({
                email: customerEmail,
                name: customerName,
                bookingRefs: allBookingRefs,
            });
            console.log(`📋 Found ${bookings.length} matching bookings`);

            // Build context for AI
            const bookingContext = buildBookingContext(bookings);

            // Call Claude API with system prompt as separate parameter
            const Anthropic = require('@anthropic-ai/sdk').default;
            const anthropic = new Anthropic({
                apiKey: process.env.ANTHROPIC_API_KEY,
            });

            // Get today's date in Iceland timezone for the AI
            const now = new Date();
            const icelandDate = new Date(now.toLocaleString('en-US', { timeZone: 'Atlantic/Reykjavik' }));
            const todayStr = icelandDate.toISOString().split('T')[0];
            const dayOfWeek = icelandDate.toLocaleDateString('en-US', { weekday: 'long', timeZone: 'Atlantic/Reykjavik' });

            const userMessage = `
TODAY'S DATE: ${todayStr} (${dayOfWeek}) - Iceland Time
IMPORTANT: Any reschedule date MUST be in the future (${todayStr} or later). Never suggest past dates.

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
                messages: [{ role: 'user', content: userMessage }],
                system: AI_SYSTEM_PROMPT,  // Use system parameter correctly
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

            // Post-process CHANGE_PICKUP actions to include pickup place ID
            if (aiResult.suggestedAction?.type === 'CHANGE_PICKUP' && bookings.length > 0) {
                const pickupName = aiResult.suggestedAction?.params?.newPickupLocation;
                console.log(`📍 CHANGE_PICKUP action detected, pickup name: "${pickupName}"`);

                const booking = bookings[0];
                const productBooking = booking.productBookings?.[0];

                const correctBookingId = String(booking.id);
                const correctProductBookingId = booking.productBookingId || productBooking?.id || null;
                const productId = booking.productId || productBooking?.product?.id || productBooking?.productId || null;

                console.log(`📋 Booking IDs: bookingId=${correctBookingId}, productBookingId=${correctProductBookingId}, productId=${productId}`);

                // Ensure params object exists
                if (!aiResult.suggestedAction.params) {
                    aiResult.suggestedAction.params = {};
                }

                // Override booking ID with the correct one from our lookup
                aiResult.suggestedAction.bookingId = correctBookingId;

                // Add productBookingId to params
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
                        if (aiResult.suggestedAction.humanReadableDescription) {
                            aiResult.suggestedAction.humanReadableDescription +=
                                ' (Note: Pickup place ID not found - may need manual update)';
                        }
                    }
                } else if (!productId) {
                    console.log(`⚠️ No product ID found in booking - cannot lookup pickup place`);
                }
            }

            // Log the AI assist request for training
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
                status: 'pending',
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                createdBy: request.auth.uid,
            });

            console.log('✅ AI Assist generated successfully');

            // Return in the format expected by the frontend
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
                    pickupLocation: b.pickupPlaceName || b.pickupPlace,
                })),
            };
        } catch (error) {
            console.error('❌ AI Assist error:', error);
            throw new Error(`AI Assist failed: ${error.message}`);
        }
    }
);

module.exports = {
    // Helper functions
    getBookingContextForAi,
    generateDraftWithClaude,
    findCustomerBookings,
    refreshAIBookingCache,
    searchBokunBookingById,
    searchBokunBookingsByEmail,
    findPickupPlaceId,
    buildBookingContext,
    // Cloud Functions
    generateAiDraft,
    generateBookingAiAssist,
};
