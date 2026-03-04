/**
 * Photo Delivery Module
 * Handles automated photo link generation for tour guests.
 * 
 * Flow:
 * 1. Guest selects tour date and enters guide name on the website widget
 * 2. Cloud Function verifies guide worked that date (Firestore shifts)
 * 3. Finds the matching Google Drive folder
 * 4. Generates a shareable link
 * 5. Checks end-of-shift report to determine if review links should be shown
 */
const { onRequest } = require('firebase-functions/v2/https');
const { google } = require('googleapis');
const { db } = require('../utils/firebase');
const { getGoogleAuth } = require('../utils/google_auth');
const { PHOTO_ROOT_FOLDER_NAME, TRIPADVISOR_REVIEW_URL, GOOGLE_MAPS_REVIEW_URL } = require('../config');

/**
 * Month name lookup (matches the Drive folder naming convention)
 */
const MONTH_NAMES = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
];

/**
 * Transliterate Icelandic characters to English equivalents.
 * e.g. "Emil Þór" → "Emil Thor", "Tómas Nói" → "Tomas Noi"
 */
function transliterate(name) {
    const map = {
        'Þ': 'Th', 'þ': 'th',
        'Ð': 'D', 'ð': 'd',
        'Æ': 'Ae', 'æ': 'ae',
        'Ö': 'O', 'ö': 'o',
        'Á': 'A', 'á': 'a',
        'É': 'E', 'é': 'e',
        'Í': 'I', 'í': 'i',
        'Ó': 'O', 'ó': 'o',
        'Ú': 'U', 'ú': 'u',
        'Ý': 'Y', 'ý': 'y',
    };
    return name.replace(/[ÞþÐðÆæÖöÁáÉéÍíÓóÚúÝý]/g, (ch) => map[ch] || ch);
}

/**
 * Navigate a Google Drive folder path and return the final folder ID.
 * Path segments are separated by '/'.
 * Starts from Drive root (or a given parent).
 */
async function findDriveFolderByPath(drive, pathSegments, parentId = 'root') {
    let currentParentId = parentId;

    for (let i = 0; i < pathSegments.length; i++) {
        const segment = pathSegments[i];
        if (!segment) continue;

        const escapedName = segment.replace(/'/g, "\\'");
        let foundFolder = null;

        if (i === 0 && parentId === 'root') {
            // For the root folder (e.g. "Norðurljósamyndir"), it's shared with the service account
            // Try multiple search strategies to find it
            console.log(`  📂 Searching for shared root folder: "${segment}"`);

            // Strategy 1: Search all accessible files
            const queries = [
                `name = '${escapedName}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false`,
                `name = '${escapedName}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false and sharedWithMe = true`,
            ];

            for (const q of queries) {
                const res = await drive.files.list({
                    q: q,
                    fields: 'files(id, name)',
                    pageSize: 5,
                    supportsAllDrives: true,
                    includeItemsFromAllDrives: true,
                });

                if (res.data.files && res.data.files.length > 0) {
                    foundFolder = res.data.files[0];
                    console.log(`  ✅ Found root folder: "${foundFolder.name}" (${foundFolder.id})`);
                    break;
                }
            }
        } else {
            // For subfolders, search within the parent
            const query = `name = '${escapedName}' and '${currentParentId}' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false`;
            console.log(`  📂 Searching for folder: "${segment}" in parent ${currentParentId}`);

            const res = await drive.files.list({
                q: query,
                fields: 'files(id, name)',
                pageSize: 5,
                supportsAllDrives: true,
                includeItemsFromAllDrives: true,
            });

            if (res.data.files && res.data.files.length > 0) {
                foundFolder = res.data.files[0];
                console.log(`  ✅ Found folder: "${foundFolder.name}" (${foundFolder.id})`);
            }
        }

        if (!foundFolder) {
            console.log(`  ❌ Folder not found: "${segment}"`);
            return null;
        }

        currentParentId = foundFolder.id;
    }

    return currentParentId;
}

/**
 * Share a Drive folder as "anyone with the link can view".
 * Idempotent — won't fail if already shared.
 */
async function shareFolderAsViewer(drive, folderId) {
    try {
        // Check if already shared
        const perms = await drive.permissions.list({
            fileId: folderId,
            fields: 'permissions(id, type, role)',
        });

        const alreadyShared = perms.data.permissions?.some(
            (p) => p.type === 'anyone' && p.role === 'reader'
        );

        if (alreadyShared) {
            console.log('📂 Folder already shared as viewer');
            return;
        }

        await drive.permissions.create({
            fileId: folderId,
            requestBody: {
                role: 'reader',
                type: 'anyone',
            },
        });

        console.log('📂 Folder shared as "anyone with link can view"');
    } catch (error) {
        console.error('⚠️ Error sharing folder:', error.message);
        // Don't throw — sharing failure shouldn't block the response
    }
}

/**
 * Count files (non-folders) inside a Drive folder.
 */
async function countFilesInFolder(drive, folderId) {
    try {
        const res = await drive.files.list({
            q: `'${folderId}' in parents and mimeType != 'application/vnd.google-apps.folder' and trashed = false`,
            fields: 'files(id)',
            pageSize: 1000,
        });
        return res.data.files?.length || 0;
    } catch (error) {
        console.error('⚠️ Error counting files:', error.message);
        return 0;
    }
}

/**
 * Check if a guide's aurora rating qualifies for review requests.
 * Reviews should be shown if:
 * - auroraRating is 'great' or 'exceptional' (always show), OR
 * - shouldRequestReviews is true AND aurora was at least somewhat visible
 * 
 * Never show reviews if aurora was 'not_seen' or 'camera_only' — there's
 * nothing positive to review and the shouldRequestReviews toggle defaults
 * to true in the UI, so it can't be trusted alone for weak aurora nights.
 */
function shouldShowReviews(report) {
    if (!report) return false;

    const rating = report.auroraRating;

    // Never request reviews if aurora wasn't visible
    if (!rating || rating === 'not_seen' || rating === 'camera_only') {
        return false;
    }

    // Great or exceptional — always show reviews
    if (rating === 'great' || rating === 'exceptional') {
        return true;
    }

    // For 'a_little' and 'good' — only show if guide explicitly requested
    return report.shouldRequestReviews === true;
}

/**
 * GET /getPhotoLink?date=YYYY-MM-DD&guide=GuideName
 * 
 * Returns:
 * {
 *   success: true,
 *   guide: { name, photoUrl, photoCount, showReviews },
 *   reviewLinks: { tripAdvisor, googleMaps } | null
 * }
 */
const getPhotoLink = onRequest(
    {
        region: 'us-central1',
        cors: true,
        invoker: 'public',
    },
    async (req, res) => {
        console.log('📸 Photo delivery request:', req.query);

        const { date, guide } = req.query;

        // Validate inputs
        if (!date) {
            return res.status(400).json({
                success: false,
                error: 'Please select a tour date.',
            });
        }

        if (!guide) {
            return res.status(400).json({
                success: false,
                error: 'Please enter your guide\'s name.',
            });
        }

        // Parse and validate date format
        const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
        if (!dateRegex.test(date)) {
            return res.status(400).json({
                success: false,
                error: 'Invalid date format. Please use YYYY-MM-DD.',
            });
        }

        const tourDate = new Date(date + 'T00:00:00Z');
        if (isNaN(tourDate.getTime())) {
            return res.status(400).json({
                success: false,
                error: 'Invalid date.',
            });
        }

        // Don't allow future dates
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        if (tourDate > today) {
            return res.status(400).json({
                success: false,
                error: 'Cannot request photos for future dates.',
            });
        }

        try {
            // -------------------------------------------------------
            // Step 1: Verify the guide worked on this date (Firestore)
            // -------------------------------------------------------
            const guideName = guide.trim();

            // Dart's DateTime.toIso8601String() produces dates WITHOUT 'Z' suffix
            // e.g. "2026-03-02T00:00:00.000" — we must match this format for Firestore string comparisons
            const startOfDayNoZ = `${date}T00:00:00.000`;
            const endOfDayNoZ = `${date}T23:59:59.999`;
            // Also try with Z suffix in case some entries use it
            const startOfDayZ = `${date}T00:00:00.000Z`;
            const endOfDayZ = `${date}T23:59:59.999Z`;

            console.log(`🔍 Querying shifts between "${startOfDayNoZ}" and "${endOfDayZ}"`);

            // Query with a broad range that covers both formats (no-Z sorts before Z in ASCII)
            const shiftsSnap = await db.collection('shifts')
                .where('date', '>=', startOfDayNoZ)
                .where('date', '<=', endOfDayZ)
                .get();

            console.log(`🔍 Found ${shiftsSnap.docs.length} total shift documents for date range`);

            // Filter for accepted/completed shifts with matching guide name
            // Transliterates Icelandic characters so guests without Icelandic keyboard can match
            const normalizedSearch = transliterate(guideName).toLowerCase();

            const matchingShifts = shiftsSnap.docs.filter((doc) => {
                const data = doc.data();
                const status = data.status;
                const fullName = (data.guideName || '').trim();
                const normalizedFull = transliterate(fullName).toLowerCase();
                return (
                    (status === 'accepted' || status === 'completed') &&
                    normalizedFull === normalizedSearch
                );
            });

            if (matchingShifts.length > 0) {
                matchingShifts.forEach((doc) => {
                    const data = doc.data();
                    console.log(`  ✅ Matched shift: guide="${data.guideName}", status=${data.status}`);
                });
            }

            if (matchingShifts.length === 0) {
                // Check if there were any shifts at all on this date
                const anyShifts = shiftsSnap.docs.filter((doc) => {
                    const data = doc.data();
                    return data.status === 'accepted' || data.status === 'completed';
                });

                if (anyShifts.length === 0) {
                    return res.json({
                        success: false,
                        error: 'No tour was found for this date. Please check the date and try again.',
                    });
                }

                return res.json({
                    success: false,
                    error: `No guide named "${guideName}" was found for this date. Please check the name and try again.`,
                    hint: 'The guide name should match exactly as introduced on the tour.',
                });
            }

            console.log(`✅ Found ${matchingShifts.length} shift(s) for guide "${guideName}" on ${date}`);

            // -------------------------------------------------------
            // Step 2: Find the Google Drive photo folder
            // -------------------------------------------------------
            const year = tourDate.getUTCFullYear().toString();
            const month = MONTH_NAMES[tourDate.getUTCMonth()];
            const day = tourDate.getUTCDate().toString();
            const dateFolder = `${day} ${month}`;

            // Use the actual guide name from Firestore for Drive path (preserves casing)
            const firestoreGuideName = matchingShifts[0].data().guideName.trim();
            const pathSegments = [PHOTO_ROOT_FOLDER_NAME, year, month, dateFolder, firestoreGuideName];

            console.log(`📁 Looking for Drive folder: ${pathSegments.join('/')}`);

            const auth = await getGoogleAuth();
            const drive = google.drive({ version: 'v3', auth });

            const folderId = await findDriveFolderByPath(drive, pathSegments);

            if (!folderId) {
                return res.json({
                    success: false,
                    error: 'Photos for this date have not been uploaded yet. Please check back later or email photo@auroraviking.com.',
                });
            }

            // -------------------------------------------------------
            // Step 3: Share the folder and count photos
            // -------------------------------------------------------
            await shareFolderAsViewer(drive, folderId);
            const photoCount = await countFilesInFolder(drive, folderId);

            const photoUrl = `https://drive.google.com/drive/folders/${folderId}`;

            console.log(`📸 Found ${photoCount} photos in folder, URL: ${photoUrl}`);

            // -------------------------------------------------------
            // Step 4: Check end-of-shift report for review eligibility
            // -------------------------------------------------------
            let showReviews = false;

            const reportsSnap = await db.collection('end_of_shift_reports')
                .where('date', '==', date) // date stored as YYYY-MM-DD string
                .get();

            // Find the report for this specific guide (transliterated match)
            const guideReport = reportsSnap.docs.find((doc) => {
                const data = doc.data();
                const reportName = transliterate((data.guideName || '').trim()).toLowerCase();
                return reportName === normalizedSearch;
            });

            if (guideReport) {
                const reportData = guideReport.data();
                showReviews = shouldShowReviews(reportData);
                console.log(`📝 End-of-shift report found: aurora=${reportData.auroraRating}, requestReviews=${reportData.shouldRequestReviews}, showReviews=${showReviews}`);
            } else {
                console.log('📝 No end-of-shift report found for this guide');
            }

            // -------------------------------------------------------
            // Step 5: Build response
            // -------------------------------------------------------
            const response = {
                success: true,
                guide: {
                    name: transliterate(firestoreGuideName),
                    photoUrl: photoUrl,
                    photoCount: photoCount,
                    showReviews: showReviews,
                },
            };

            if (showReviews) {
                response.reviewLinks = {
                    tripAdvisor: TRIPADVISOR_REVIEW_URL,
                    googleMaps: GOOGLE_MAPS_REVIEW_URL,
                };
            }

            console.log('✅ Photo delivery response sent successfully');
            return res.json(response);

        } catch (error) {
            console.error('❌ Photo delivery error:', error);
            return res.status(500).json({
                success: false,
                error: 'Something went wrong. Please try again or email photo@auroraviking.com.',
            });
        }
    }
);

module.exports = {
    getPhotoLink,
};
