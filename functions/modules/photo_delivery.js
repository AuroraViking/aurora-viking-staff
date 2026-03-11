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
 * e.g. "Emil ÃžÃ³r" â†’ "Emil Thor", "TÃ³mas NÃ³i" â†’ "Tomas Noi"
 */
function transliterate(name) {
    const map = {
        'Ãž': 'Th', 'Ã¾': 'th',
        'Ã': 'D', 'Ã°': 'd',
        'Ã†': 'Ae', 'Ã¦': 'ae',
        'Ã–': 'O', 'Ã¶': 'o',
        'Ã': 'A', 'Ã¡': 'a',
        'Ã‰': 'E', 'Ã©': 'e',
        'Ã': 'I', 'Ã­': 'i',
        'Ã“': 'O', 'Ã³': 'o',
        'Ãš': 'U', 'Ãº': 'u',
        'Ã': 'Y', 'Ã½': 'y',
    };
    return name.replace(/[ÃžÃ¾ÃÃ°Ã†Ã¦Ã–Ã¶ÃÃ¡Ã‰Ã©ÃÃ­Ã“Ã³ÃšÃºÃÃ½]/g, (ch) => map[ch] || ch);
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
            // For the root folder (e.g. "NorÃ°urljÃ³samyndir"), it's shared with the service account
            // Try multiple search strategies to find it
            console.log(`  ðŸ“‚ Searching for shared root folder: "${segment}"`);

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
                    console.log(`  âœ… Found root folder: "${foundFolder.name}" (${foundFolder.id})`);
                    break;
                }
            }
        } else {
            // For subfolders, search within the parent
            const query = `name = '${escapedName}' and '${currentParentId}' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false`;
            console.log(`  ðŸ“‚ Searching for folder: "${segment}" in parent ${currentParentId}`);

            const res = await drive.files.list({
                q: query,
                fields: 'files(id, name)',
                pageSize: 5,
                supportsAllDrives: true,
                includeItemsFromAllDrives: true,
            });

            if (res.data.files && res.data.files.length > 0) {
                foundFolder = res.data.files[0];
                console.log(`  âœ… Found folder: "${foundFolder.name}" (${foundFolder.id})`);
            }
        }

        if (!foundFolder) {
            console.log(`  âŒ Folder not found: "${segment}"`);
            return null;
        }

        currentParentId = foundFolder.id;
    }

    return currentParentId;
}

/**
 * Share a Drive folder as "anyone with the link can view".
 * Idempotent â€” won't fail if already shared.
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
            console.log('ðŸ“‚ Folder already shared as viewer');
            return;
        }

        await drive.permissions.create({
            fileId: folderId,
            requestBody: {
                role: 'reader',
                type: 'anyone',
            },
        });

        console.log('ðŸ“‚ Folder shared as "anyone with link can view"');
    } catch (error) {
        console.error('âš ï¸ Error sharing folder:', error.message);
        // Don't throw â€” sharing failure shouldn't block the response
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
        console.error('âš ï¸ Error counting files:', error.message);
        return 0;
    }
}

/**
 * Check if a guide's aurora rating qualifies for review requests.
 * Reviews should be shown if:
 * - auroraRating is 'great' or 'exceptional' (always show), OR
 * - shouldRequestReviews is true AND aurora was at least somewhat visible
 * 
 * Never show reviews if aurora was 'not_seen' or 'camera_only' â€” there's
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

    // Great or exceptional â€” always show reviews
    if (rating === 'great' || rating === 'exceptional') {
        return true;
    }

    // For 'a_little' and 'good' â€” only show if guide explicitly requested
    return report.shouldRequestReviews === true;
}

/**
 * Log a photo request to Firestore for analytics.
 * Fire-and-forget â€” never blocks the response.
 */
function logPhotoRequest(req, { date, guide, success, photoCount, showReviews, error }) {
    const ip = req.headers['x-forwarded-for'] || req.ip || 'unknown';
    const userAgent = req.headers['user-agent'] || 'unknown';

    db.collection('photo_requests').add({
        date: date || null,
        guide: guide || null,
        success: success,
        photoCount: photoCount || 0,
        showReviews: showReviews || false,
        error: error || null,
        ip: ip,
        userAgent: userAgent,
        timestamp: new Date().toISOString(),
    }).catch((err) => {
        console.error('âš ï¸ Failed to log photo request:', err.message);
    });
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
        console.log('ðŸ“¸ Photo delivery request:', req.query);

        const { date, guide, listGuides } = req.query;

        // Validate inputs
        if (!date) {
            return res.status(400).json({
                success: false,
                error: 'Please select a tour date.',
            });
        }

        // -------------------------------------------------------
        // List Guides mode: return guide names for a date (from Drive folders)
        // -------------------------------------------------------
        if (listGuides === 'true') {
            try {
                const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
                if (!dateRegex.test(date)) {
                    return res.json({ success: true, guides: [] });
                }

                const tourDate = new Date(date + 'T00:00:00Z');
                const year = tourDate.getUTCFullYear().toString();
                const month = MONTH_NAMES[tourDate.getUTCMonth()];
                const day = tourDate.getUTCDate().toString();
                const dateFolder = `${day} ${month}`;

                console.log(`ðŸ“‹ Looking for guide folders in: ${PHOTO_ROOT_FOLDER_NAME}/${year}/${month}/${dateFolder}`);

                // Navigate to the date folder in Google Drive
                const auth = await getGoogleAuth();
                const drive = google.drive({ version: 'v3', auth });

                const dateFolderId = await findDriveFolderByPath(
                    drive,
                    [PHOTO_ROOT_FOLDER_NAME, year, month, dateFolder],
                );

                if (!dateFolderId) {
                    console.log(`ðŸ“‹ No date folder found for ${dateFolder}`);
                    return res.json({ success: true, guides: [] });
                }

                // List all subfolders (guide names) in the date folder
                const foldersRes = await drive.files.list({
                    q: `'${dateFolderId}' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false`,
                    fields: 'files(id, name)',
                    pageSize: 50,
                    supportsAllDrives: true,
                    includeItemsFromAllDrives: true,
                });

                const guideNames = (foldersRes.data.files || [])
                    .map(f => f.name)
                    .sort();

                console.log(`ðŸ“‹ Found ${guideNames.length} guide folders for ${date}: ${JSON.stringify(guideNames)}`);
                return res.json({ success: true, guides: guideNames });
            } catch (err) {
                console.error('âŒ listGuides error:', err);
                return res.json({ success: true, guides: [] });
            }
        }

        if (!guide) {
            return res.status(400).json({
                success: false,
                error: 'Please select your guide.',
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
            // Step 1: Find the Google Drive photo folder directly
            // No shift verification  we go straight to Drive
            // -------------------------------------------------------
            const guideName = guide.trim();
            const normalizedSearch = transliterate(guideName).toLowerCase();

            const year = tourDate.getUTCFullYear().toString();
            const month = MONTH_NAMES[tourDate.getUTCMonth()];
            const day = tourDate.getUTCDate().toString();
            const dateFolder = `${day} ${month}`;

            const auth = await getGoogleAuth();
            const drive = google.drive({ version: 'v3', auth });

            // Find the date folder first
            const dateFolderId = await findDriveFolderByPath(
                drive,
                [PHOTO_ROOT_FOLDER_NAME, year, month, dateFolder],
            );

            if (!dateFolderId) {
                logPhotoRequest(req, {
                    date,
                    guide: guideName,
                    success: false,
                    error: 'No tour found for this date',
                });
                return res.json({
                    success: false,
                    error: 'No tour was found for this date. Please check the date and try again.',
                });
            }

            // Try exact guide name first (covers dropdown selection)
            let folderId = await findDriveFolderByPath(drive, [guideName], dateFolderId);

            // If not found, try transliterated name
            if (!folderId) {
                const transliteratedName = transliterate(guideName);
                if (transliteratedName !== guideName) {
                    console.log(`📁 Exact name not found, trying transliterated: "${transliteratedName}"`);
                    folderId = await findDriveFolderByPath(drive, [transliteratedName], dateFolderId);
                }
            }

            // If still not found, try fuzzy match against available folders
            if (!folderId) {
                const foldersRes = await drive.files.list({
                    q: `'${dateFolderId}' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false`,
                    fields: 'files(id, name)',
                    pageSize: 50,
                    supportsAllDrives: true,
                    includeItemsFromAllDrives: true,
                });

                const availableGuides = (foldersRes.data.files || []).map(f => f.name);
                console.log(`❌ No folder for "${guideName}". Available: ${JSON.stringify(availableGuides)}`);

                const fuzzyMatch = (foldersRes.data.files || []).find(f => {
                    const n = transliterate(f.name).toLowerCase();
                    return n.includes(normalizedSearch) || normalizedSearch.includes(n);
                });

                if (fuzzyMatch) {
                    folderId = fuzzyMatch.id;
                    console.log(`✅ Fuzzy matched to folder: "${fuzzyMatch.name}"`);
                } else {
                    logPhotoRequest(req, {
                        date,
                        guide: guideName,
                        success: false,
                        error: `Guide not found: ${guideName}`,
                    });
                    return res.json({
                        success: false,
                        error: availableGuides.length > 0
                            ? `No guide named "${guideName}" was found for this date. Please check the name and try again.`
                            : 'Photos for this date have not been uploaded yet. Please check back later or email photo@auroraviking.com.',
                    });
                }
            }

            console.log(`✅ Found folder for guide "${guideName}" on ${date}`);

            // -------------------------------------------------------
            // Step 2: Share the folder and count photos
            // -------------------------------------------------------
            await shareFolderAsViewer(drive, folderId);
            const photoCount = await countFilesInFolder(drive, folderId);

            const photoUrl = `https://drive.google.com/drive/folders/${folderId}`;

            console.log(`ðŸ“¸ Found ${photoCount} photos in folder, URL: ${photoUrl}`);

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
                console.log(`ðŸ“ End-of-shift report found: aurora=${reportData.auroraRating}, requestReviews=${reportData.shouldRequestReviews}, showReviews=${showReviews}`);
            } else {
                console.log('ðŸ“ No end-of-shift report found for this guide');
            }

            // -------------------------------------------------------
            // Step 5: Build response
            // -------------------------------------------------------
            const response = {
                success: true,
                guide: {
                    name: guideName,
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

            console.log('âœ… Photo delivery response sent successfully');

            // Log successful request
            logPhotoRequest(req, {
                date,
                guide: guideName,
                success: true,
                photoCount: photoCount,
                showReviews: showReviews,
            });

            return res.json(response);

        } catch (error) {
            console.error('âŒ Photo delivery error:', error);

            // Log failed request
            logPhotoRequest(req, {
                date,
                guide: guide,
                success: false,
                error: error.message || 'Internal error',
            });

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
