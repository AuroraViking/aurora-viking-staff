/**
 * Push Notification Utilities
 * Handles sending FCM notifications to users
 */
const { admin, db } = require('./firebase');

/**
 * Send notification to ADMIN users only
 * Filters users by isAdmin === true
 */
async function sendNotificationToAdminsOnly(title, body, data = {}) {
    try {
        console.log(`📤 Preparing to send admin-only notification: "${title}"`);

        // Get users with isAdmin = true
        const usersSnapshot = await db
            .collection('users')
            .where('isAdmin', '==', true)
            .get();

        console.log(`👥 Found ${usersSnapshot.size} admin users in database`);

        // If no admins found with isAdmin field, fallback to role check
        if (usersSnapshot.empty) {
            console.log('⚠️ No users with isAdmin=true, trying role=admin fallback...');
            const fallbackSnapshot = await db
                .collection('users')
                .where('role', '==', 'admin')
                .get();

            if (fallbackSnapshot.empty) {
                console.log('⚠️ No admin users found to send notification');
                return { success: false, message: 'No admin users found' };
            }

            const tokens = [];
            const adminNames = [];
            fallbackSnapshot.forEach((doc) => {
                const userData = doc.data();
                if (userData.fcmToken) {
                    tokens.push(userData.fcmToken);
                    adminNames.push(userData.fullName || userData.email || doc.id);
                }
            });

            if (tokens.length === 0) {
                return { success: false, message: 'No FCM tokens found for admins' };
            }

            return await sendPushNotifications(tokens, title, body, data, adminNames);
        }

        const tokens = [];
        const adminNames = [];
        usersSnapshot.forEach((doc) => {
            const userData = doc.data();
            if (userData.fcmToken) {
                tokens.push(userData.fcmToken);
                adminNames.push(userData.fullName || userData.email || doc.id);
            }
        });

        console.log(`📱 Found ${tokens.length} FCM tokens for admin users`);

        if (tokens.length === 0) {
            console.log('⚠️ No FCM tokens found for admin users');
            return { success: false, message: 'No FCM tokens found for admins' };
        }

        return await sendPushNotifications(tokens, title, body, data, adminNames);
    } catch (error) {
        console.error('❌ Error sending notification to admins:', error);
        return { success: false, error: error.message };
    }
}

/**
 * Send push notification to all users
 */
async function sendNotificationToAdmins(title, body, data = {}) {
    try {
        console.log(`📤 Preparing to send notification: "${title}" - "${body}"`);

        // Get all users
        const usersSnapshot = await db.collection('users').get();

        console.log(`👥 Found ${usersSnapshot.size} users in database`);

        if (usersSnapshot.empty) {
            console.log('⚠️ No users found to send notification');
            return { success: false, message: 'No users found' };
        }

        const tokens = [];
        usersSnapshot.forEach((doc) => {
            const userData = doc.data();
            if (userData.fcmToken) {
                tokens.push(userData.fcmToken);
            }
        });

        console.log(`📱 Found ${tokens.length} FCM tokens out of ${usersSnapshot.size} users`);

        if (tokens.length === 0) {
            console.log('⚠️ No FCM tokens found for users');
            return { success: false, message: 'No FCM tokens found' };
        }

        // Send notification to all tokens
        const messages = tokens.map((token) => ({
            notification: { title, body },
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
                    aps: { sound: 'default' },
                },
            },
        }));

        const response = await admin.messaging().sendEach(messages);

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
        return { success: false, error: error.message };
    }
}

/**
 * Helper function to send push notifications
 */
async function sendPushNotifications(tokens, title, body, data, recipientNames) {
    const messages = tokens.map((token) => ({
        notification: { title, body },
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
                aps: { sound: 'default' },
            },
        },
    }));

    const response = await admin.messaging().sendEach(messages);

    console.log(`✅ Notification sent to ${response.successCount} admin(s): ${recipientNames.join(', ')}`);
    if (response.failureCount > 0) {
        console.log(`⚠️ Failed to send to ${response.failureCount} admin(s)`);
    }

    return {
        success: true,
        sent: response.successCount,
        failed: response.failureCount,
        recipients: recipientNames,
    };
}

/**
 * Get a Google Maps link for coordinates
 */
function getGoogleMapsLink(latitude, longitude) {
    if (!latitude || !longitude) return null;
    return `https://maps.google.com/?q=${latitude},${longitude}`;
}

/**
 * Get emoji for aurora level
 */
function getAuroraEmoji(level) {
    const emojis = {
        'weak': '🌌',
        'medium': '✨',
        'strong': '🔥',
        'exceptional': '🤯',
    };
    return emojis[level] || '🌌';
}

module.exports = {
    sendNotificationToAdminsOnly,
    sendNotificationToAdmins,
    sendPushNotifications,
    getGoogleMapsLink,
    getAuroraEmoji,
};
