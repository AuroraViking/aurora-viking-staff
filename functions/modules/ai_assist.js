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

    prompt += `\nLatest Customer Message:\n${message}\n\nGenerate a draft response. Be helpful, professional, and friendly. If you detect this is about a booking change, mention that.`;

    const response = await anthropic.messages.create({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 1024,
        messages: [
            {
                role: 'user',
                content: prompt,
            },
        ],
    });

    const text = response.content[0].text;

    return {
        content: text,
        confidence: 0.8,
        tone: 'professional',
        reasoning: 'Generated based on message content and context',
    };
}

/**
 * Find customer bookings by email, name, or booking references
 */
async function findCustomerBookings({ email, name, bookingRefs }) {
    const accessKey = process.env.BOKUN_ACCESS_KEY;
    const secretKey = process.env.BOKUN_SECRET_KEY;

    const results = [];
    const seenIds = new Set();

    // 1. Search by booking references first (most reliable)
    if (bookingRefs && bookingRefs.length > 0) {
        console.log(`🔍 Searching ${bookingRefs.length} booking refs...`);

        for (const ref of bookingRefs) {
            // Try numeric ID
            const numericMatch = ref.match(/\d+/);
            if (numericMatch) {
                const numericId = numericMatch[0];

                // Check AI cache first
                const cacheDoc = await db.collection('ai_booking_cache').doc(numericId).get();
                if (cacheDoc.exists) {
                    const booking = cacheDoc.data();
                    if (!seenIds.has(booking.id)) {
                        seenIds.add(booking.id);
                        results.push({
                            ...booking,
                            matchConfidence: 'HIGH',
                            matchReason: `Matched by booking ref: ${ref}`,
                        });
                    }
                    continue;
                }

                // Try Bokun API
                if (accessKey && secretKey) {
                    try {
                        const booking = await searchBokunBookingById(numericId, accessKey, secretKey);
                        if (booking && !seenIds.has(booking.id)) {
                            seenIds.add(booking.id);
                            results.push({
                                ...booking,
                                matchConfidence: 'HIGH',
                                matchReason: `Found in Bokun by ID: ${numericId}`,
                            });
                        }
                    } catch (e) {
                        console.log(`⚠️ Bokun search failed for ${numericId}`);
                    }
                }
            }
        }
    }

    // 2. Search by email
    if (email && accessKey && secretKey) {
        console.log(`🔍 Searching by email: ${email}`);
        try {
            const emailBookings = await searchBokunBookingsByEmail(email, accessKey, secretKey);
            for (const booking of emailBookings) {
                if (!seenIds.has(booking.id)) {
                    seenIds.add(booking.id);
                    results.push({
                        ...booking,
                        matchConfidence: 'MEDIUM',
                        matchReason: `Matched by email: ${email}`,
                    });
                }
            }
        } catch (e) {
            console.log(`⚠️ Email search failed: ${e.message}`);
        }
    }

    // 3. Check AI cache by email
    if (email) {
        const cacheQuery = await db.collection('ai_booking_cache')
            .where('customerEmail', '==', email)
            .limit(10)
            .get();

        for (const doc of cacheQuery.docs) {
            const booking = doc.data();
            if (!seenIds.has(booking.id)) {
                seenIds.add(booking.id);
                results.push({
                    ...booking,
                    matchConfidence: 'MEDIUM',
                    matchReason: `Found in cache by email`,
                });
            }
        }
    }

    console.log(`📋 Found ${results.length} total bookings`);
    return results;
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
        const pickupPlace = booking.pickupPlace ||
            productBooking?.fields?.pickupPlace?.title ||
            booking.pickupPlaceName ||
            'Not assigned yet';
        const pickupPlaceId = booking.pickupPlaceId || productBooking?.fields?.pickupPlace?.id || null;
        const customerEmail = booking.customerEmail || booking.customer?.email || 'Unknown';
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
// CLOUD FUNCTIONS
// ============================================

/**
 * Generate AI draft response when new inbound message is created
 * DEPRECATED: Now using on-demand generateBookingAiAssist instead to save tokens
 */
const generateAiDraft = onDocumentCreated(
    {
        document: 'messages/{messageId}',
        region: 'us-central1',
        secrets: ['ANTHROPIC_API_KEY'],
    },
    async (event) => {
        // DISABLED: Auto AI draft generation is disabled to save on API tokens
        // Use the on-demand generateBookingAiAssist function instead
        console.log('⏭️ Auto AI draft generation is disabled. Use generateBookingAiAssist instead.');
        return null;

        // Original implementation preserved for reference:
        /*
        const snapshot = event.data;
        if (!snapshot) return null;
    
        const messageData = snapshot.data();
        const messageId = event.params.messageId;
    
        if (messageData.direction !== 'inbound') {
          console.log('⏭️ Skipping AI draft - not inbound message');
          return null;
        }
    
        console.log('🧠 Generating AI draft for message:', messageId);
    
        try {
          const conversationId = messageData.conversationId;
          const messagesSnapshot = await db.collection('messages')
            .where('conversationId', '==', conversationId)
            .orderBy('timestamp', 'asc')
            .limit(10)
            .get();
    
          const conversationHistory = messagesSnapshot.docs.map(doc => doc.data());
    
          const bookingContext = await getBookingContextForAi(messageData.detectedBookingNumbers);
    
          const draft = await generateDraftWithClaude({
            message: messageData.content,
            customer: null,
            bookingContext,
            conversationHistory,
          });
    
          await snapshot.ref.update({
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
          return { success: false, error: error.message };
        }
        */
    }
);

/**
 * On-demand AI Booking Assist
 * Called when staff wants AI help for a specific message
 */
const generateBookingAiAssist = onCall(
    {
        region: 'us-central1',
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
            const extractedRefs = new Set();

            // Pattern for various booking formats
            const patterns = [
                /\b(?:AUR|VIA|GET|BKN|TUI)-?\s*(\d{6,10})\b/gi,  // Prefixed refs
                /\b(\d{8,10})\b/g,  // Pure numeric refs
            ];

            for (const pattern of patterns) {
                let match;
                while ((match = pattern.exec(messageContent)) !== null) {
                    const ref = match[1] || match[0];
                    const numericRef = ref.replace(/\D/g, '');
                    if (numericRef.length >= 6) {
                        extractedRefs.add(numericRef);
                        console.log(`🔍 Found booking reference in message: ${match[0]} -> ${numericRef}`);
                    }
                }
            }

            // Add any explicitly passed refs
            if (bookingRefs) {
                for (const ref of bookingRefs) {
                    const numericRef = ref.replace(/\D/g, '');
                    if (numericRef.length >= 6) {
                        extractedRefs.add(numericRef);
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

            // Build booking context for AI
            const bookingContext = buildBookingContext(bookings);

            // Call Claude API
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
                        content: AI_SYSTEM_PROMPT + '\n\n' + userMessage,
                    },
                ],
            });

            const responseText = response.content[0].text;

            // Parse JSON response
            let aiResult;
            try {
                const jsonMatch = responseText.match(/\{[\s\S]*\}/);
                if (jsonMatch) {
                    aiResult = JSON.parse(jsonMatch[0]);
                } else {
                    throw new Error('No JSON found in response');
                }
            } catch (parseError) {
                console.log('⚠️ Could not parse AI response as JSON, using text response');
                aiResult = {
                    suggestedReply: responseText,
                    suggestedAction: { type: 'INFO_ONLY' },
                    confidence: 0.5,
                    reasoning: 'Could not parse structured response',
                };
            }

            // Post-process CHANGE_PICKUP actions to include pickup place ID
            if (aiResult.suggestedAction?.type === 'CHANGE_PICKUP' && bookings.length > 0) {
                const pickupName = aiResult.suggestedAction?.params?.newPickupLocation;
                console.log(`📍 CHANGE_PICKUP action detected, pickup name: "${pickupName}"`);

                const bestBooking = bookings[0];
                const productBooking = bestBooking.productBookings?.[0];
                const productId = bestBooking.productId || productBooking?.product?.id;
                const correctBookingId = bestBooking.id;
                const correctProductBookingId = bestBooking.productBookingId || productBooking?.id;

                aiResult.suggestedAction.bookingId = correctBookingId;

                if (correctProductBookingId) {
                    aiResult.suggestedAction.params = aiResult.suggestedAction.params || {};
                    aiResult.suggestedAction.params.productBookingId = correctProductBookingId;
                    console.log(`✅ Added productBookingId ${correctProductBookingId} to action`);
                }

                if (pickupName && productId) {
                    const pickupPlace = await findPickupPlaceId(productId, pickupName);
                    if (pickupPlace) {
                        aiResult.suggestedAction.params = aiResult.suggestedAction.params || {};
                        aiResult.suggestedAction.params.pickupPlaceId = pickupPlace.id;
                        aiResult.suggestedAction.params.pickupPlaceName = pickupPlace.title;
                        console.log(`✅ Added pickupPlaceId ${pickupPlace.id} to action`);
                    } else {
                        console.log(`⚠️ Could not find pickup place ID for "${pickupName}"`);
                        if (aiResult.suggestedReply) {
                            aiResult.suggestedReply += ' (Note: Pickup place ID not found - may need manual update)';
                        }
                    }
                }
            }

            // Log the AI assist request
            await db.collection('ai_assist_logs').add({
                conversationId,
                customerEmail,
                customerName,
                bookingRefs: bookingRefs || [],
                extractedRefs: allBookingRefs,
                messageContent: messageContent.substring(0, 500),
                aiResponse: aiResult,
                bookingsFound: bookings.length,
                userId: request.auth.uid,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            return {
                success: true,
                aiResponse: aiResult,
                bookingsFound: bookings.map(b => ({
                    id: b.id,
                    confirmationCode: b.confirmationCode,
                    customerName: b.customer?.fullName || b.customerFullName,
                    startDate: b.startDate || b.productBookings?.[0]?.startDate,
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

module.exports = {
    // Helper functions
    getBookingContextForAi,
    generateDraftWithClaude,
    findCustomerBookings,
    searchBokunBookingById,
    searchBokunBookingsByEmail,
    findPickupPlaceId,
    buildBookingContext,
    // Cloud Functions
    generateAiDraft,
    generateBookingAiAssist,
};
