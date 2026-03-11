/**
 * Photo Upload Module
 * Handles server-side upload of photos/videos to Google Drive.
 * 
 * Architecture:
 *   1. preparePhotoUpload – Creates Drive folder, returns folderId
 *   2. uploadFileChunk   – Receives a base64 chunk, writes to GCS via admin SDK
 *   3. finalizeFileUpload – Composes chunks, uploads assembled file to Drive, cleans up
 *
 * This avoids client-side Firebase Storage SDK issues on web.
 * Chunks are ~5 MB raw (≈6.7 MB base64), well under the 10 MB callable limit.
 */
const { onCall } = require('firebase-functions/v2/https');
const { google } = require('googleapis');
const { admin } = require('../utils/firebase');
const { getGoogleAuth } = require('../utils/google_auth');
const { PHOTO_ROOT_FOLDER_NAME } = require('../config');

// Email of the account that owns the Drive photo folder
const DRIVE_OWNER_EMAIL = 'photo@auroraviking.com';
const SA_EMAIL = '975783791718-compute@developer.gserviceaccount.com';

/**
 * Get an access token impersonating photo@auroraviking.com
 * Uses IAM signJwt API to create a JWT with subject claim (no key file needed).
 * Requires domain-wide delegation + signJwt permission on the service account.
 */
async function getDriveAuthAsPhotoUser() {
    const { IAMCredentialsClient } = require('@google-cloud/iam-credentials');
    const iamClient = new IAMCredentialsClient();

    const now = Math.floor(Date.now() / 1000);
    const jwtPayload = {
        iss: SA_EMAIL,
        sub: DRIVE_OWNER_EMAIL,
        scope: 'https://www.googleapis.com/auth/drive https://www.googleapis.com/auth/drive.file',
        aud: 'https://oauth2.googleapis.com/token',
        iat: now,
        exp: now + 3600,
    };

    // Sign the JWT using IAM API (no key file needed)
    const [signResponse] = await iamClient.signJwt({
        name: `projects/-/serviceAccounts/${SA_EMAIL}`,
        payload: JSON.stringify(jwtPayload),
    });

    const signedJwt = signResponse.signedJwt;

    // Exchange signed JWT for an access token
    const fetch = require('node-fetch');
    const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${signedJwt}`,
    });

    const tokenData = await tokenResponse.json();
    if (tokenData.error) {
        throw new Error(`Token exchange failed: ${tokenData.error_description || tokenData.error}`);
    }

    // Return an OAuth2 client with the access token
    const oauth2Client = new google.auth.OAuth2();
    oauth2Client.setCredentials({ access_token: tokenData.access_token });
    return oauth2Client;
}

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

function getMimeType(fileName) {
    const ext = fileName.toLowerCase().split('.').pop();
    const m = { jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', heic: 'image/heic', arw: 'image/x-sony-arw', raw: 'image/raw', cr2: 'image/x-canon-cr2', cr3: 'image/x-canon-cr2', nef: 'image/x-nikon-nef', mp4: 'video/mp4', mov: 'video/quicktime', avi: 'video/x-msvideo', mkv: 'video/x-matroska', mts: 'video/mp2t', webm: 'video/webm' };
    return m[ext] || 'application/octet-stream';
}

// ── 1. Create Drive folder ──
const preparePhotoUpload = onCall(
    { region: 'us-central1', timeoutSeconds: 60 },
    async (request) => {
        if (!request.auth) throw new Error('Authentication required.');
        const { guideName, date } = request.data;
        if (!guideName || !date) throw new Error('Missing guideName or date');

        const d = new Date(date + 'T00:00:00Z');
        const folderPath = [PHOTO_ROOT_FOLDER_NAME, d.getUTCFullYear().toString(), MONTH_NAMES[d.getUTCMonth()], `${d.getUTCDate()} ${MONTH_NAMES[d.getUTCMonth()]}`, transliterate(guideName)];
        console.log(`📁 ${folderPath.join('/')}`);

        const auth = await getGoogleAuth();
        const drive = google.drive({ version: 'v3', auth });
        const folderId = await createDriveFolderPath(drive, folderPath);
        return { success: true, folderId, driveUrl: `https://drive.google.com/drive/folders/${folderId}` };
    }
);

// ── 2. Receive a file chunk and store in GCS via admin SDK ──
const uploadFileChunk = onCall(
    { region: 'us-central1', timeoutSeconds: 120, memory: '512MiB' },
    async (request) => {
        if (!request.auth) throw new Error('Authentication required.');
        const { uploadId, chunkIndex, totalChunks, chunkData, fileName } = request.data;
        if (!uploadId || chunkIndex === undefined || !chunkData) throw new Error('Missing params');

        const bucket = admin.storage().bucket();
        const chunkPath = `temp_chunks/${uploadId}/chunk_${String(chunkIndex).padStart(4, '0')}`;

        const buffer = Buffer.from(chunkData, 'base64');
        console.log(`📦 Chunk ${chunkIndex + 1}/${totalChunks} for ${fileName}: ${(buffer.length / 1024).toFixed(0)} KB → ${chunkPath}`);

        const file = bucket.file(chunkPath);
        await file.save(buffer, { resumable: false });

        return { success: true, chunkIndex, stored: chunkPath };
    }
);

// ── 3. Assemble chunks and upload to Google Drive ──
const finalizeFileUpload = onCall(
    { region: 'us-central1', timeoutSeconds: 540, memory: '1GiB' },
    async (request) => {
        if (!request.auth) throw new Error('Authentication required.');
        const { uploadId, fileName, folderId, fileIndex, totalChunks } = request.data;
        if (!uploadId || !fileName || !folderId) throw new Error('Missing params');

        console.log(`🔗 Assembling ${totalChunks} chunks for ${fileName}...`);
        const bucket = admin.storage().bucket();

        try {
            // Download all chunks in order
            const buffers = [];
            for (let i = 0; i < totalChunks; i++) {
                const chunkPath = `temp_chunks/${uploadId}/chunk_${String(i).padStart(4, '0')}`;
                const [data] = await bucket.file(chunkPath).download();
                buffers.push(data);
            }
            const fullBuffer = Buffer.concat(buffers);
            console.log(`📄 Assembled file: ${(fullBuffer.length / 1024 / 1024).toFixed(1)} MB`);

            // Upload to Google Drive (as photo@auroraviking.com to have storage quota)
            const auth = await getDriveAuthAsPhotoUser();
            const drive = google.drive({ version: 'v3', auth });
            const { Readable } = require('stream');
            const stream = new Readable();
            stream.push(fullBuffer);
            stream.push(null);

            const paddedIndex = (fileIndex || 0).toString().padStart(3, '0');
            const driveFileName = `${paddedIndex}_${fileName}`;

            await drive.files.create({
                requestBody: { name: driveFileName, parents: [folderId] },
                media: { mimeType: getMimeType(fileName), body: stream },
                supportsAllDrives: true,
            });
            console.log(`✅ Uploaded to Drive: ${driveFileName}`);

            // Clean up chunks
            for (let i = 0; i < totalChunks; i++) {
                const p = `temp_chunks/${uploadId}/chunk_${String(i).padStart(4, '0')}`;
                await bucket.file(p).delete().catch(() => { });
            }
            console.log(`🧹 Cleaned up ${totalChunks} chunks`);

            return { success: true, fileName: driveFileName };
        } catch (error) {
            console.error(`❌ finalizeFileUpload error: ${error.message}`);
            throw new Error(`Finalize failed: ${error.message}`);
        }
    }
);

module.exports = { preparePhotoUpload, uploadFileChunk, finalizeFileUpload };
