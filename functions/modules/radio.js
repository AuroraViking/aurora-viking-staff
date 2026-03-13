/**
 * Voice Radio Cloud Functions
 * Sends push notifications when a new radio message is posted (voice, text, or image).
 */
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { db } = require('../utils/firebase');
const { sendPushNotifications } = require('../utils/notifications');

/**
 * Triggered when a new radio_messages document is created.
 * Determines the channel type, gathers recipient FCM tokens,
 * and sends push notifications so offline users hear about the message.
 */
const onRadioMessageCreated = onDocumentCreated(
    {
        document: 'radio_messages/{messageId}',
        region: 'us-central1',
    },
    async (event) => {
        const snap = event.data;
        if (!snap) return;

        const data = snap.data();
        const { channelId, senderName, senderId, durationMs, type, textContent } = data;
        const messageType = type || 'voice';
        const durationSecs = Math.ceil((durationMs || 0) / 1000);

        console.log(`📻 New radio ${messageType} message from ${senderName} on channel ${channelId}`);

        // Determine the channel info.
        const channelDoc = await db.collection('radio_channels').doc(channelId).get();
        if (!channelDoc.exists) {
            console.warn('⚠️ Channel not found:', channelId);
            return;
        }

        const channel = channelDoc.data();
        const channelName = channel.name || channelId;
        const channelType = channel.type || 'fleet';

        // Gather FCM tokens based on channel type.
        let tokens = [];
        let recipientNames = [];

        if (channelType === 'fleet' || channelType === 'dispatch') {
            // Send to all staff except the sender.
            const usersSnap = await db.collection('users').get();
            usersSnap.forEach((doc) => {
                if (doc.id === senderId) return; // Don't notify sender.
                const u = doc.data();
                if (u.fcmToken) {
                    tokens.push(u.fcmToken);
                    recipientNames.push(u.fullName || u.email || doc.id);
                }
            });
        } else if (channelType === 'direct') {
            // Send only to the other member(s) of the direct channel.
            const members = channel.members || [];
            const targetMembers = members.filter((id) => id !== senderId);

            for (const memberId of targetMembers) {
                const userDoc = await db.collection('users').doc(memberId).get();
                if (userDoc.exists) {
                    const u = userDoc.data();
                    if (u.fcmToken) {
                        tokens.push(u.fcmToken);
                        recipientNames.push(u.fullName || u.email || memberId);
                    }
                }
            }
        }

        if (tokens.length === 0) {
            console.log('⚠️ No recipients with FCM tokens for this radio message');
            return;
        }

        const title = `📻 ${senderName} on #${channelName}`;

        // Build body based on message type.
        let body;
        if (messageType === 'text') {
            const preview = (textContent || '').length > 80
                ? (textContent || '').substring(0, 80) + '...'
                : (textContent || '');
            body = preview || 'New text message';
        } else if (messageType === 'image') {
            body = '📷 Sent a photo';
        } else {
            body = `🎙 Voice message (${durationSecs}s)`;
        }

        await sendPushNotifications(tokens, title, body, {
            type: 'radio_message',
            channelId: channelId,
            messageId: event.params.messageId,
        }, recipientNames);
    }
);

module.exports = {
    onRadioMessageCreated,
};
