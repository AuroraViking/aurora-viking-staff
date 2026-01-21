/**
 * Website Chat Widget Module
 * Handles website chat sessions and messaging
 */
const { onRequest } = require('firebase-functions/v2/https');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const crypto = require('crypto');
const { admin, db } = require('../utils/firebase');
const { sendNotificationToAdminsOnly } = require('../utils/notifications');

/**
 * Verify Firebase Auth token from request
 * Returns the decoded token with uid, or null if invalid
 */
async function verifyWebsiteAuth(req) {
    // Skip verification for OPTIONS requests (CORS preflight)
    if (req.method === 'OPTIONS') {
        return { uid: 'preflight' };
    }

    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        console.log('❌ No auth header or not Bearer format');
        return null;
    }

    try {
        const token = authHeader.split('Bearer ')[1];
        const decodedToken = await admin.auth().verifyIdToken(token);
        return decodedToken;
    } catch (error) {
        console.log('❌ Token verification failed:', error.message);
        return null;
    }
}

/**
 * Create a new anonymous website chat session
 */
const createWebsiteSession = onRequest(
    {
        region: 'us-central1',
        cors: true,
    },
    async (req, res) => {
        console.log('🌐 Creating website chat session...');

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
            const customerRef = await db.collection('customers').add({
                name: 'Website Visitor',
                email: null,
                phone: null,
                channels: {
                    website: sessionId,
                },
                totalBookings: 0,
                vipStatus: false,
                language: 'en',
                firstContact: admin.firestore.FieldValue.serverTimestamp(),
                lastContact: admin.firestore.FieldValue.serverTimestamp(),
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // Create conversation
            const conversationRef = await db.collection('conversations').add({
                customerId: customerRef.id,
                channel: 'website',
                status: 'active',
                lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
                lastMessagePreview: '',
                unreadCount: 0,
                messageIds: [],
                bookingIds: [],
                channelMetadata: {
                    website: {
                        sessionId: sessionId,
                        firstPageUrl: pageUrl || null,
                        referrer: referrer || null,
                    }
                },
                inboxEmail: 'website',
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // Create website session document
            await db.collection('website_sessions').doc(sessionId).set({
                sessionId: sessionId,
                conversationId: conversationRef.id,
                customerId: customerRef.id,
                visitorName: null,
                visitorEmail: null,
                firstPageUrl: pageUrl || null,
                referrer: referrer || null,
                userAgent: userAgent || null,
                status: 'active',
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                lastActivityAt: admin.firestore.FieldValue.serverTimestamp(),
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
 */
const updateWebsiteSession = onRequest(
    {
        region: 'us-central1',
        cors: true,
    },
    async (req, res) => {
        const authUser = await verifyWebsiteAuth(req);
        if (!authUser) {
            return res.status(401).json({ error: 'Unauthorized' });
        }

        try {
            const { sessionId, visitorName, visitorEmail, currentPageUrl } = req.body;

            if (!sessionId) {
                return res.status(400).json({ error: 'sessionId is required' });
            }

            const sessionDoc = await db.collection('website_sessions').doc(sessionId).get();
            if (!sessionDoc.exists) {
                return res.status(404).json({ error: 'Session not found' });
            }

            const updates = {
                lastActivityAt: admin.firestore.FieldValue.serverTimestamp(),
            };

            if (visitorName) updates.visitorName = visitorName;
            if (visitorEmail) updates.visitorEmail = visitorEmail;
            if (currentPageUrl) updates.currentPageUrl = currentPageUrl;

            await db.collection('website_sessions').doc(sessionId).update(updates);

            // Also update customer if email/name provided
            const sessionData = sessionDoc.data();
            if ((visitorName || visitorEmail) && sessionData.customerId) {
                const customerUpdates = {};
                if (visitorName) customerUpdates.name = visitorName;
                if (visitorEmail) {
                    customerUpdates.email = visitorEmail;
                    customerUpdates['channels.gmail'] = visitorEmail;
                }
                customerUpdates.updatedAt = admin.firestore.FieldValue.serverTimestamp();

                await db.collection('customers').doc(sessionData.customerId).update(customerUpdates);
            }

            res.json({ success: true });
        } catch (error) {
            console.error('❌ Error updating website session:', error);
            res.status(500).json({ error: error.message });
        }
    }
);

/**
 * Send message from website visitor
 */
const sendWebsiteMessage = onRequest(
    {
        region: 'us-central1',
        cors: true,
    },
    async (req, res) => {
        const authUser = await verifyWebsiteAuth(req);
        if (!authUser) {
            return res.status(401).json({ error: 'Unauthorized' });
        }

        try {
            const { sessionId, content, visitorName, visitorEmail } = req.body;

            if (!sessionId || !content) {
                return res.status(400).json({ error: 'sessionId and content are required' });
            }

            const sessionDoc = await db.collection('website_sessions').doc(sessionId).get();
            if (!sessionDoc.exists) {
                return res.status(404).json({ error: 'Session not found' });
            }

            const session = sessionDoc.data();

            // Update visitor info if provided
            if (visitorName || visitorEmail) {
                const sessionUpdates = {};
                if (visitorName) sessionUpdates.visitorName = visitorName;
                if (visitorEmail) sessionUpdates.visitorEmail = visitorEmail;
                sessionUpdates.lastActivityAt = admin.firestore.FieldValue.serverTimestamp();

                await db.collection('website_sessions').doc(sessionId).update(sessionUpdates);

                // Also update customer
                if (session.customerId) {
                    const customerUpdates = {};
                    if (visitorName) customerUpdates.name = visitorName;
                    if (visitorEmail) {
                        customerUpdates.email = visitorEmail;
                        customerUpdates['channels.gmail'] = visitorEmail;
                    }
                    customerUpdates.updatedAt = admin.firestore.FieldValue.serverTimestamp();

                    await db.collection('customers').doc(session.customerId).update(customerUpdates);
                }
            }

            // Create message
            const messageData = {
                conversationId: session.conversationId,
                customerId: session.customerId,
                channel: 'website',
                direction: 'inbound',
                content: content,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                channelMetadata: {
                    website: {
                        sessionId: sessionId,
                        visitorName: visitorName || session.visitorName || null,
                        visitorEmail: visitorEmail || session.visitorEmail || null,
                    },
                },
                bookingIds: [],
                detectedBookingNumbers: [],
                status: 'pending',
                flaggedForReview: false,
                priority: 'normal',
            };

            const msgRef = await db.collection('messages').add(messageData);
            console.log(`💬 Website message created: ${msgRef.id}`);

            // Update conversation
            await db.collection('conversations').doc(session.conversationId).update({
                lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
                lastMessagePreview: content.substring(0, 100),
                unreadCount: admin.firestore.FieldValue.increment(1),
                messageIds: admin.firestore.FieldValue.arrayUnion(msgRef.id),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // Update session activity
            await db.collection('website_sessions').doc(sessionId).update({
                lastActivityAt: admin.firestore.FieldValue.serverTimestamp(),
                messageCount: admin.firestore.FieldValue.increment(1),
            });

            res.json({
                success: true,
                messageId: msgRef.id,
            });
        } catch (error) {
            console.error('❌ Error sending website message:', error);
            res.status(500).json({ error: error.message });
        }
    }
);

/**
 * Update visitor presence (heartbeat)
 */
const updateWebsitePresence = onRequest(
    {
        region: 'us-central1',
        cors: true,
    },
    async (req, res) => {
        const authUser = await verifyWebsiteAuth(req);
        if (!authUser) {
            return res.status(401).json({ error: 'Unauthorized' });
        }

        try {
            const { sessionId, currentPageUrl } = req.body;

            if (!sessionId) {
                return res.status(400).json({ error: 'sessionId is required' });
            }

            const sessionDoc = await db.collection('website_sessions').doc(sessionId).get();
            if (!sessionDoc.exists) {
                return res.status(404).json({ error: 'Session not found' });
            }

            const updates = {
                lastActivityAt: admin.firestore.FieldValue.serverTimestamp(),
                status: 'active',
            };

            if (currentPageUrl) {
                updates.currentPageUrl = currentPageUrl;
            }

            await db.collection('website_sessions').doc(sessionId).update(updates);

            res.json({ success: true });
        } catch (error) {
            console.error('❌ Error updating presence:', error);
            res.status(500).json({ error: error.message });
        }
    }
);

/**
 * Send reply to website visitor (staff sends from admin app)
 */
const sendWebsiteChatReply = onRequest(
    {
        region: 'us-central1',
        cors: true,
    },
    async (req, res) => {
        const authHeader = req.headers.authorization;
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            return res.status(401).json({ error: 'Unauthorized' });
        }

        try {
            const token = authHeader.split('Bearer ')[1];
            const decodedToken = await admin.auth().verifyIdToken(token);
            const uid = decodedToken.uid;

            const { conversationId, content } = req.body;

            if (!conversationId || !content) {
                return res.status(400).json({ error: 'conversationId and content are required' });
            }

            const convDoc = await db.collection('conversations').doc(conversationId).get();
            if (!convDoc.exists) {
                return res.status(404).json({ error: 'Conversation not found' });
            }

            const conv = convDoc.data();

            // Create outbound message
            const messageData = {
                conversationId,
                customerId: conv.customerId,
                channel: 'website',
                direction: 'outbound',
                content: content,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                channelMetadata: {
                    website: {
                        sessionId: conv.channelMetadata?.website?.sessionId || null,
                    },
                },
                bookingIds: [],
                detectedBookingNumbers: [],
                status: 'sent',
                handledBy: uid,
                handledAt: admin.firestore.FieldValue.serverTimestamp(),
            };

            const msgRef = await db.collection('messages').add(messageData);
            console.log(`📤 Website reply sent: ${msgRef.id}`);

            // Update conversation
            await convDoc.ref.update({
                lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
                lastMessagePreview: content.substring(0, 100),
                unreadCount: 0,
                messageIds: admin.firestore.FieldValue.arrayUnion(msgRef.id),
                status: 'active',
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            res.json({
                success: true,
                messageId: msgRef.id,
            });
        } catch (error) {
            console.error('❌ Error sending website reply:', error);
            res.status(500).json({ error: error.message });
        }
    }
);

/**
 * Firestore trigger: Send notification when new website chat message arrives
 */
const onWebsiteChatMessage = onDocumentCreated(
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

        // Only process inbound website messages
        if (messageData.channel !== 'website' || messageData.direction !== 'inbound') {
            console.log(`ℹ️ Skipping notification - not an inbound website message`);
            return null;
        }

        console.log(`💬 New website chat message received: ${messageId}`);

        try {
            // Get conversation for more context
            const conversationDoc = await db.collection('conversations').doc(messageData.conversationId).get();
            const conversationData = conversationDoc.exists ? conversationDoc.data() : {};

            // Get visitor info
            const visitorName = messageData.channelMetadata?.website?.visitorName || 'Website Visitor';
            const visitorEmail = messageData.channelMetadata?.website?.visitorEmail || '';

            // Send push notification to admins
            const title = '💬 New Website Chat';
            const body = `${visitorName}: ${messageData.content.substring(0, 100)}${messageData.content.length > 100 ? '...' : ''}`;

            await sendNotificationToAdminsOnly(title, body, {
                type: 'website_chat',
                messageId: messageId,
                conversationId: messageData.conversationId,
                visitorEmail: visitorEmail,
            });

            console.log(`✅ Notification sent for website chat message: ${messageId}`);
            return { success: true };

        } catch (error) {
            console.error(`❌ Error sending website chat notification:`, error);
            return { success: false, error: error.message };
        }
    }
);

module.exports = {
    verifyWebsiteAuth,
    createWebsiteSession,
    updateWebsiteSession,
    sendWebsiteMessage,
    updateWebsitePresence,
    sendWebsiteChatReply,
    onWebsiteChatMessage,
};
