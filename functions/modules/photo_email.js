/**
 * Photo Email Module
 * Sends automated photo folder links to customers ~1 hour after tour departure.
 *
 * Flow:
 *   1. Scheduled function runs every hour during aurora season
 *   2. Checks tour_status — skips if OFF or not set (cancelled)
 *   3. Checks departure time — only fires ~1h after departure
 *   4. For each guide in pickup_assignments:
 *      - Creates their Drive folder (Norðurljósamyndir/{year}/{month}/{day month}/{guide}/)
 *      - Shares folder as "anyone with link can view"
 *      - Sends email to only that guide's customers with the folder link
 *   5. Guide uploads later — findOrCreateFolder detects existing folder automatically
 */
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall } = require('firebase-functions/v2/https');
const { google } = require('googleapis');
const { admin, db } = require('../utils/firebase');
const { getGoogleAuth } = require('../utils/google_auth');
const { PHOTO_ROOT_FOLDER_NAME } = require('../config');

// ── Reusable helpers ──

const MONTH_NAMES = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
];

function transliterate(name) {
    const map = {
        'Þ': 'Th', 'þ': 'th', 'Ð': 'D', 'ð': 'd',
        'Æ': 'Ae', 'æ': 'ae', 'Ö': 'O', 'ö': 'o',
        'Á': 'A', 'á': 'a', 'É': 'E', 'é': 'e',
        'Í': 'I', 'í': 'i', 'Ó': 'O', 'ó': 'o',
        'Ú': 'U', 'ú': 'u', 'Ý': 'Y', 'ý': 'y',
    };
    return name.replace(/[ÞþÐðÆæÖöÁáÉéÍíÓóÚúÝý]/g, (ch) => map[ch] || ch);
}

function getTodayDateStr() {
    const now = new Date();
    const iceland = new Date(now.toLocaleString('en-US', { timeZone: 'Atlantic/Reykjavik' }));
    return `${iceland.getFullYear()}-${String(iceland.getMonth() + 1).padStart(2, '0')}-${String(iceland.getDate()).padStart(2, '0')}`;
}

function isAuroraSeason() {
    const now = new Date();
    const month = now.getMonth() + 1;
    const day = now.getDate();
    if (month >= 5 && month <= 7) return false;
    if (month === 8 && day < 15) return false;
    return true;
}

// ── Gmail helpers (same pattern as tour_status.js) ──

function getGmailOAuth2Client(clientId, clientSecret) {
    return new google.auth.OAuth2(
        clientId,
        clientSecret,
        'https://us-central1-aurora-viking-staff.cloudfunctions.net/gmailOAuthCallback'
    );
}

async function getGmailTokens(email) {
    const emailId = email.replace(/[.@]/g, '_');
    const doc = await db.collection('system').doc('gmail_accounts').collection('accounts').doc(emailId).get();
    if (doc.exists) return doc.data();
    const oldDoc = await db.collection('system').doc('gmail_tokens').get();
    if (oldDoc.exists) return oldDoc.data();
    return null;
}

async function getGmailClient(email, clientId, clientSecret) {
    const tokens = await getGmailTokens(email);
    if (!tokens) throw new Error(`No Gmail tokens found for ${email}`);
    const oauth2Client = getGmailOAuth2Client(clientId, clientSecret);
    oauth2Client.setCredentials({
        access_token: tokens.accessToken || tokens.access_token,
        refresh_token: tokens.refreshToken || tokens.refresh_token,
        expiry_date: tokens.expiryDate || tokens.expiry_date,
    });
    return google.gmail({ version: 'v1', auth: oauth2Client });
}

// ── Drive helpers (same patterns as photo_upload.js) ──

async function findOrCreateFolder(drive, folderName, parentId) {
    const escapedName = folderName.replace(/'/g, "\\'");
    if (parentId === 'root') {
        for (const extra of ['', ' and sharedWithMe = true']) {
            const q = `name = '${escapedName}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false${extra}`;
            const res = await drive.files.list({ q, fields: 'files(id)', pageSize: 5, supportsAllDrives: true, includeItemsFromAllDrives: true });
            if (res.data.files?.length) return res.data.files[0].id;
        }
    } else {
        const q = `name = '${escapedName}' and '${parentId}' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false`;
        const res = await drive.files.list({ q, fields: 'files(id)', pageSize: 5, supportsAllDrives: true, includeItemsFromAllDrives: true });
        if (res.data.files?.length) return res.data.files[0].id;
    }
    const r = await drive.files.create({ requestBody: { name: folderName, mimeType: 'application/vnd.google-apps.folder', parents: [parentId] }, fields: 'id', supportsAllDrives: true });
    return r.data.id;
}

async function createDriveFolderPath(drive, segments) {
    let pid = 'root';
    for (const s of segments) { if (s) pid = await findOrCreateFolder(drive, s, pid); }
    return pid;
}

async function shareFolderAsViewer(drive, folderId) {
    try {
        const perms = await drive.permissions.list({
            fileId: folderId,
            fields: 'permissions(id, type, role)',
        });
        const alreadyShared = perms.data.permissions?.some(
            (p) => p.type === 'anyone' && p.role === 'reader'
        );
        if (alreadyShared) return;

        await drive.permissions.create({
            fileId: folderId,
            requestBody: { role: 'reader', type: 'anyone' },
        });
        console.log('📂 Folder shared as "anyone with link can view"');
    } catch (error) {
        console.error('⚠️ Error sharing folder:', error.message);
    }
}

// ── Email HTML builder ──

function buildPhotoEmailHtml(firstName, guideName, folderUrl) {
    return `<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#1a1a2e;font-family:Arial,Helvetica,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#1a1a2e;padding:20px 0;">
<tr><td align="center">
<table width="600" cellpadding="0" cellspacing="0" style="background:#16213e;border-radius:12px;overflow:hidden;max-width:100%;">
  <tr><td style="background:linear-gradient(135deg,#0f3460,#1b4332);padding:30px;text-align:center;">
    <h1 style="color:#d4af37;margin:0;font-size:22px;letter-spacing:1px;">AURORA VIKING</h1>
    <p style="color:#ccc;margin:8px 0 0;font-size:13px;">Your Tour Photos 📸</p>
  </td></tr>
  <tr><td style="padding:30px;color:#e0e0e0;font-size:15px;line-height:1.7;">
    <p>Hi ${firstName},</p>
    <p>Thank you for joining us on the Northern Lights tour tonight with <strong style="color:#d4af37;">${guideName}</strong>! We hope you had an amazing experience.</p>
    <p>Your guide will be uploading the professional photos from tonight's tour to the folder below. <strong>Photos can take up to 48 hours to appear</strong>, so please check back if the folder is still empty.</p>
    <div style="text-align:center;margin:25px 0;">
      <a href="${folderUrl}" style="display:inline-block;background:linear-gradient(135deg,#d4af37,#b8941e);color:#0f1729;text-decoration:none;padding:14px 32px;border-radius:8px;font-weight:bold;font-size:16px;letter-spacing:0.5px;">View Your Photos</a>
    </div>
    <div style="background:#1a1a2e;border-left:4px solid #d4af37;padding:15px 20px;margin:15px 0;border-radius:0 8px 8px 0;">
      <p style="margin:0;color:#8892a8;font-size:13px;">📌 <strong style="color:#e0e0e0;">Bookmark this link</strong> — you can come back anytime to view and download your photos. It can take up to 48 hours for photos to appear in the folder.</p>
    </div>
    <p>If you had a great time, we'd love to hear about it! A review on TripAdvisor or Google Maps helps us more than you know.</p>
    <p>All the best,<br>
    <strong>The Aurora Viking Team</strong></p>
  </td></tr>
  <tr><td style="background:#0f3460;padding:20px;text-align:center;color:#888;font-size:12px;">
    Aurora Viking &bull; <a href="mailto:photo@auroraviking.com" style="color:#4fc3f7;">photo@auroraviking.com</a> &bull; +354 784 4000
  </td></tr>
</table>
</td></tr></table>
</body></html>`;
}

// ── Core logic ──

async function sendPhotoEmails(dateStr) {
    console.log(`📸 Photo email check for ${dateStr}...`);

    // 1. Check tour status — skip if OFF or not set
    const statusDoc = await db.collection('tour_status').doc(dateStr).get();
    if (!statusDoc.exists) {
        console.log(`⏭️ No tour status set for ${dateStr}, skipping`);
        return { success: true, skipped: true, reason: 'no_tour_status' };
    }
    const tourStatus = statusDoc.data().status;
    if (tourStatus !== 'ON') {
        console.log(`⏭️ Tour status is ${tourStatus} for ${dateStr}, skipping`);
        return { success: true, skipped: true, reason: `tour_${tourStatus}` };
    }

    // 2. Check dedup — don't send twice
    const dedupDoc = await db.collection('photo_emails_sent').doc(dateStr).get();
    if (dedupDoc.exists) {
        console.log(`⏭️ Photo emails already sent for ${dateStr}`);
        return { success: true, skipped: true, reason: 'already_sent' };
    }

    // 3. Check departure time — only proceed if ≥1h after departure
    const cachedDoc = await db.collection('cached_bookings').doc(dateStr).get();
    if (!cachedDoc.exists) {
        console.log(`⏭️ No cached_bookings for ${dateStr}`);
        return { success: true, skipped: true, reason: 'no_bookings' };
    }
    const bookings = cachedDoc.data().bookings || [];
    if (bookings.length === 0) {
        console.log(`⏭️ No bookings for ${dateStr}`);
        return { success: true, skipped: true, reason: 'no_bookings' };
    }

    // Find departure time (usually consistent across bookings)
    let departureMinutes = null;
    for (const booking of bookings) {
        const dt = booking.departureTime || booking.pickupTime;
        if (dt && typeof dt === 'string' && dt.includes(':')) {
            const parts = dt.split(':');
            departureMinutes = parseInt(parts[0]) * 60 + parseInt(parts[1]);
            break;
        }
    }

    if (departureMinutes === null) {
        console.log('⚠️ Could not determine departure time, proceeding anyway');
    } else {
        const now = new Date();
        const iceland = new Date(now.toLocaleString('en-US', { timeZone: 'Atlantic/Reykjavik' }));
        const nowMinutes = iceland.getHours() * 60 + iceland.getMinutes();
        const minutesSinceDeparture = nowMinutes - departureMinutes;

        console.log(`⏰ Departure at ${Math.floor(departureMinutes / 60)}:${String(departureMinutes % 60).padStart(2, '0')}, now ${iceland.getHours()}:${String(iceland.getMinutes()).padStart(2, '0')}, ${minutesSinceDeparture} min since departure`);

        if (minutesSinceDeparture < 60) {
            console.log(`⏭️ Only ${minutesSinceDeparture} min since departure, waiting for 60+`);
            return { success: true, skipped: true, reason: 'too_early', minutesSinceDeparture };
        }
    }

    // 4. Get guide → customer mapping from pickup_assignments
    const assignmentsSnap = await db.collection('pickup_assignments')
        .where('date', '==', dateStr)
        .get();

    // Filter to guide-level docs (they have a bookings array)
    const guideAssignments = [];
    for (const doc of assignmentsSnap.docs) {
        const data = doc.data();
        if (data.guideName && data.bookings && Array.isArray(data.bookings) && data.bookings.length > 0) {
            guideAssignments.push(data);
        }
    }

    if (guideAssignments.length === 0) {
        console.log(`⏭️ No guide assignments found for ${dateStr}`);
        return { success: true, skipped: true, reason: 'no_assignments' };
    }

    console.log(`👥 Found ${guideAssignments.length} guides with assignments`);

    // 5. Setup Gmail + Drive
    const clientId = process.env.GMAIL_CLIENT_ID;
    const clientSecret = process.env.GMAIL_CLIENT_SECRET;
    if (!clientId || !clientSecret) {
        console.log('⚠️ Gmail keys not available');
        return { success: false, error: 'Gmail keys not configured' };
    }

    const fromEmail = 'info@auroraviking.com';
    const gmail = await getGmailClient(fromEmail, clientId, clientSecret);
    const auth = await getGoogleAuth();
    const drive = google.drive({ version: 'v3', auth });

    // Parse date for Drive folder path
    const d = new Date(dateStr + 'T00:00:00Z');
    const year = d.getUTCFullYear().toString();
    const month = MONTH_NAMES[d.getUTCMonth()];
    const dayFolder = `${d.getUTCDate()} ${month}`;

    let totalEmailsSent = 0;
    let totalFailed = 0;
    const guideResults = [];

    // 6. For each guide: create folder + send emails
    for (const assignment of guideAssignments) {
        const guideName = transliterate(assignment.guideName.trim());
        const folderPath = [PHOTO_ROOT_FOLDER_NAME, year, month, dayFolder, guideName];

        console.log(`📁 Creating folder: ${folderPath.join('/')}`);
        const folderId = await createDriveFolderPath(drive, folderPath);
        await shareFolderAsViewer(drive, folderId);

        const folderUrl = `https://drive.google.com/drive/folders/${folderId}`;
        console.log(`📂 Folder ready: ${folderUrl}`);

        // Send emails to this guide's customers
        const emails = new Set();
        let guideSent = 0;

        for (const booking of assignment.bookings) {
            const email = (booking.email || '').toLowerCase().trim();
            if (!email || emails.has(email)) continue;
            emails.add(email);

            const fullName = booking.customerFullName || 'Valued Customer';
            const firstName = fullName.split(' ')[0] || 'there';

            const htmlBody = buildPhotoEmailHtml(firstName, assignment.guideName, folderUrl);

            const emailLines = [
                `From: Aurora Viking <${fromEmail}>`,
                `Reply-To: photo@auroraviking.com`,
                `To: ${email}`,
                `Subject: Your Aurora Viking Tour Photos 📸`,
                'MIME-Version: 1.0',
                'Content-Type: text/html; charset=utf-8',
                '',
                htmlBody,
            ];

            const rawMessage = Buffer.from(emailLines.join('\r\n'))
                .toString('base64')
                .replace(/\+/g, '-')
                .replace(/\//g, '_')
                .replace(/=+$/, '');

            try {
                await gmail.users.messages.send({
                    userId: 'me',
                    requestBody: { raw: rawMessage },
                });
                guideSent++;
                totalEmailsSent++;
                console.log(`✅ Sent photo email to ${firstName} (${email}) — guide: ${guideName}`);
            } catch (sendError) {
                console.error(`❌ Failed to send to ${email}: ${sendError.message}`);
                totalFailed++;
            }

            // Rate limiting
            if (emails.size > 3) {
                await new Promise(resolve => setTimeout(resolve, 500));
            }
        }

        guideResults.push({
            guideName: assignment.guideName,
            folderId,
            folderUrl,
            emailsSent: guideSent,
        });

        console.log(`📧 Guide ${guideName}: ${guideSent} emails sent`);
    }

    // 7. Log to prevent re-sending
    await db.collection('photo_emails_sent').doc(dateStr).set({
        date: dateStr,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        totalEmailsSent,
        totalFailed,
        guides: guideResults,
    });

    console.log(`✅ Photo emails complete: ${totalEmailsSent} sent, ${totalFailed} failed`);

    return {
        success: true,
        date: dateStr,
        totalEmailsSent,
        totalFailed,
        guides: guideResults,
    };
}

// ============================================
// EXPORTED CLOUD FUNCTIONS
// ============================================

/**
 * Scheduled: Run every hour, checks if photo emails should be sent
 */
const photoEmailScheduled = onSchedule(
    {
        schedule: 'every 1 hours',
        timeZone: 'Atlantic/Reykjavik',
        region: 'us-central1',
        secrets: ['GMAIL_CLIENT_ID', 'GMAIL_CLIENT_SECRET'],
        timeoutSeconds: 300,
    },
    async () => {
        console.log('📸 Scheduled photo email check...');

        if (!isAuroraSeason()) {
            console.log('☀️ Not aurora season, skipping');
            return;
        }

        try {
            const dateStr = getTodayDateStr();
            const result = await sendPhotoEmails(dateStr);
            console.log('📸 Photo email result:', JSON.stringify(result));
            return result;
        } catch (error) {
            console.error('❌ Photo email scheduled error:', error);
            return null;
        }
    }
);

/**
 * Manual trigger for testing
 */
const photoEmailManual = onCall(
    {
        region: 'us-central1',
        secrets: ['GMAIL_CLIENT_ID', 'GMAIL_CLIENT_SECRET'],
        timeoutSeconds: 300,
    },
    async (request) => {
        if (!request.auth) {
            throw new Error('Authentication required');
        }
        const { date } = request.data || {};
        const dateStr = date || getTodayDateStr();
        console.log(`📸 Manual photo email triggered for ${dateStr} by ${request.auth.uid}`);
        return await sendPhotoEmails(dateStr);
    }
);

module.exports = {
    photoEmailScheduled,
    photoEmailManual,
};
