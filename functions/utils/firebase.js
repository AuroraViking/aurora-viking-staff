/**
 * Firebase Admin SDK initialization
 * Shared across all modules
 */
const admin = require('firebase-admin');

// Initialize Firebase Admin (only once)
if (!admin.apps.length) {
    admin.initializeApp();
}

const db = admin.firestore();

module.exports = {
    admin,
    db,
};
