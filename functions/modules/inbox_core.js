/**
 * Unified Inbox Core Module
 * Shared inbox utilities and message processing
 */
const { onCall } = require('firebase-functions/v2/https');
const { admin, db } = require('../utils/firebase');

/**
 * Extract booking references from message content
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
        const customerDoc = snapshot.docs[0];
        await customerDoc.ref.update({
            lastContact: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return customerDoc.id;
    }

    let extractedName = name;
    if (!extractedName && channel === 'gmail') {
        extractedName = identifier.split('@')[0].replace(/[._]/g, ' ');
        extractedName = extractedName.split(' ')
            .map(w => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase())
            .join(' ');
    }

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
async function findOrCreateConversation(customerId, channel, threadId, subject, messagePreview, inboxEmail = null) {
    const conversationsRef = db.collection('conversations');

    let snapshot;
    if (channel === 'gmail' && threadId) {
        snapshot = await conversationsRef
            .where('customerId', '==', customerId)
            .where('channel', '==', channel)
            .where('channelMetadata.gmail.threadId', '==', threadId)
            .limit(1)
            .get();
    }

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
        const convDoc = snapshot.docs[0];
        await convDoc.ref.update({
            lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
            lastMessagePreview: messagePreview.substring(0, 100),
            unreadCount: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return convDoc.id;
    }

    const newConversation = {
        customerId,
        channel,
        inboxEmail: inboxEmail || null,
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
 * Process incoming Gmail message
 */
const processGmailMessage = onCall(
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
            const detectedBookingNumbers = extractBookingReferences(content + ' ' + (subject || ''));
            console.log(`🔍 Detected booking refs: ${detectedBookingNumbers.join(', ') || 'none'}`);

            const customerId = await findOrCreateCustomer('gmail', from, null);
            const conversationId = await findOrCreateConversation(
                customerId,
                'gmail',
                threadId || null,
                subject || null,
                content
            );

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
 * Send message via channel
 */
const sendInboxMessage = onCall(
    {
        region: 'us-central1',
    },
    async (request) => {
        console.log('📤 Sending inbox message');

        if (!request.auth) {
            return { success: false, error: 'Authentication required' };
        }

        const { conversationId, content, channel } = request.data;

        if (!conversationId || !content) {
            return { success: false, error: 'Missing required fields: conversationId, content' };
        }

        try {
            const convDoc = await db.collection('conversations').doc(conversationId).get();
            if (!convDoc.exists) {
                return { success: false, error: 'Conversation not found' };
            }

            const conversation = convDoc.data();

            const customerDoc = await db.collection('customers').doc(conversation.customerId).get();
            if (!customerDoc.exists) {
                return { success: false, error: 'Customer not found' };
            }

            const customer = customerDoc.data();

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

            if ((channel || conversation.channel) === 'gmail') {
                messageData.channelMetadata.gmail = {
                    to: [customer.email || customer.channels?.gmail],
                    from: 'info@auroraviking.is',
                    threadId: conversation.channelMetadata?.gmail?.threadId || '',
                };
            }

            const msgRef = await db.collection('messages').add(messageData);
            console.log(`📨 Outbound message created: ${msgRef.id}`);

            await convDoc.ref.update({
                lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
                lastMessagePreview: content.substring(0, 100),
                unreadCount: 0,
                messageIds: admin.firestore.FieldValue.arrayUnion(msgRef.id),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            return { success: true, messageId: msgRef.id };
        } catch (error) {
            console.error('❌ Error sending message:', error);
            return { success: false, error: error.message };
        }
    }
);

/**
 * Mark conversation as read
 */
const markConversationRead = onCall(
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
 * Update conversation status
 */
const updateConversationStatus = onCall(
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
            return { success: false, error: 'Invalid status' };
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
 * Create test message (for development)
 */
const createTestInboxMessage = onCall(
    {
        region: 'us-central1',
    },
    async (request) => {
        console.log('🧪 Creating test inbox message...');

        const testEmail = request.data?.email || 'test@example.com';
        const testContent = request.data?.content || 'Hi, I have a question about my booking AV-12345.';
        const testSubject = request.data?.subject || 'Question about my booking';

        try {
            const detectedBookingNumbers = extractBookingReferences(testContent + ' ' + testSubject);
            const customerId = await findOrCreateCustomer('gmail', testEmail, null);

            const threadId = `thread-${Date.now()}`;
            const conversationId = await findOrCreateConversation(
                customerId,
                'gmail',
                threadId,
                testSubject,
                testContent
            );

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

module.exports = {
    extractBookingReferences,
    findOrCreateCustomer,
    findOrCreateConversation,
    processGmailMessage,
    sendInboxMessage,
    markConversationRead,
    updateConversationStatus,
    createTestInboxMessage,
};
