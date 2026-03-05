/**
 * Booking Portal Module â€” Customer Self-Service
 * Public endpoints (no Firebase Auth) for customers to manage their own bookings.
 * Identity verified by matching name + email + confirmation code against Bokun records.
 * 
 * Endpoints:
 *   portalLookupBooking      â€” Find booking by name, email, confirmation code
 *   portalCheckAvailability  â€” Check available dates for rescheduling
 *   portalRescheduleBooking  â€” Request a reschedule
 *   portalCancelBooking      â€” Request a cancellation
 *   portalGetPickupPlaces    â€” Get available pickup locations
 *   portalUpdatePickup       â€” Change pickup location
 */
const { onRequest, onCall } = require('firebase-functions/v2/https');
const { admin, db } = require('../utils/firebase');
const { makeBokunRequest, searchBokunByConfirmationCode } = require('../utils/bokun_client');
const { sendNotificationToAdminsOnly } = require('../utils/notifications');
const crypto = require('crypto');
const https = require('https');

// â”€â”€â”€ Rate Limiting (in-memory, per-instance) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const rateLimitMap = new Map();

// â”€â”€â”€ Helper: Check if tour is cancelled/OFF for a date â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
async function isTourCancelledForDate(dateString) {
    try {
        const statusDoc = await db.collection('tour_status').doc(dateString).get();
        if (statusDoc.exists && statusDoc.data().status === 'OFF') {
            return true;
        }
    } catch (e) {
        console.log(`âš ï¸ Could not check tour status for ${dateString}: ${e.message}`);
    }
    return false;
}
const RATE_LIMIT_WINDOW_MS = 60_000; // 1 minute
const RATE_LIMIT_MAX = 10;

function isRateLimited(ip) {
    const now = Date.now();
    const entry = rateLimitMap.get(ip);
    if (!entry || now - entry.windowStart > RATE_LIMIT_WINDOW_MS) {
        rateLimitMap.set(ip, { windowStart: now, count: 1 });
        return false;
    }
    entry.count++;
    if (entry.count > RATE_LIMIT_MAX) return true;
    return false;
}

// ——— Identity Verification Helper ————————————————————————————————
/**
 * Looks up a booking by confirmation code.
 * Email and name are optional - if provided, they validate against the booking.
 * If omitted (e.g. from email link), the booking is returned directly.
 * Returns { booking, error } - booking is the raw Bokun booking object.
 */
async function verifyAndFetchBooking(confirmationCode, email, name, accessKey, secretKey) {
    if (!confirmationCode) {
        return { booking: null, error: 'Booking reference number is required' };
    }

    // Search by confirmation code
    let booking = await searchBokunByConfirmationCode(confirmationCode, accessKey, secretKey);

    if (!booking) {
        // Extract numeric ID from prefixed codes like "AUR-85873869" â†’ "85873869"
        const numericMatch = confirmationCode.match(/(\d{5,})/);
        const numericId = numericMatch ? numericMatch[1] : null;

        // Try direct booking fetch by numeric ID
        const idToTry = /^\d+$/.test(confirmationCode) ? confirmationCode : numericId;
        if (idToTry) {
            try {
                console.log(`ðŸ” Trying direct Bokun lookup by ID: ${idToTry}`);
                const directBooking = await makeBokunRequest(
                    'GET',
                    `/booking.json/${idToTry}`,
                    null,
                    accessKey,
                    secretKey
                );
                if (directBooking && directBooking.id) {
                    booking = directBooking;
                }
            } catch (e) {
                console.log(`ðŸ” Direct lookup by ID ${idToTry} failed: ${e.message}`);
            }
        }

        // If still not found, try searching by just the numeric part as confirmation code
        if (!booking && numericId && numericId !== confirmationCode) {
            console.log(`ðŸ” Trying confirmation code search with numeric part: ${numericId}`);
            booking = await searchBokunByConfirmationCode(numericId, accessKey, secretKey);
        }

        if (!booking) {
            return { booking: null, error: 'Booking not found. Please check your booking reference number.' };
        }
    }

    // If email or name provided, validate them. Otherwise return booking directly.
    if (email || name) {
        return validateBookingIdentity(booking, email, name);
    }

    return { booking, error: null };
}

function validateBookingIdentity(booking, email, name) {
    // Validate email
    const bookingEmail = (booking.customer?.email || '').toLowerCase().trim();
    const providedEmail = email.toLowerCase().trim();
    if (bookingEmail !== providedEmail) {
        return { booking: null, error: 'The details provided do not match our records. Please check your name, email, and booking reference.' };
    }

    // Validate name (flexible match â€” first name or full name)
    const firstName = (booking.customer?.firstName || '').toLowerCase().trim();
    const lastName = (booking.customer?.lastName || '').toLowerCase().trim();
    const fullName = `${firstName} ${lastName}`.trim();
    const providedName = name.toLowerCase().trim();

    const nameMatch =
        providedName === fullName ||
        providedName === firstName ||
        fullName.includes(providedName) ||
        providedName.includes(firstName);

    if (!nameMatch) {
        return { booking: null, error: 'The details provided do not match our records. Please check your name, email, and booking reference.' };
    }

    return { booking, error: null };
}

// â”€â”€â”€ Helper: Parse Bokun date to YYYY-MM-DD string â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function parseBokunDate(dateValue) {
    if (!dateValue) return null;

    // Already a string like "2026-03-05"
    if (typeof dateValue === 'string') {
        // Try to parse ISO or date string
        if (/^\d{4}-\d{2}-\d{2}/.test(dateValue)) return dateValue.substring(0, 10);
        // Try parsing any other string format
        const d = new Date(dateValue);
        if (!isNaN(d.getTime())) return d.toISOString().substring(0, 10);
        return dateValue;
    }

    // Date object from Bokun like { year: 2026, month: 3, day: 5 }
    if (typeof dateValue === 'object' && dateValue.year) {
        const y = dateValue.year;
        const m = String(dateValue.month || dateValue.monthOfYear || 1).padStart(2, '0');
        const d = String(dateValue.day || dateValue.dayOfMonth || 1).padStart(2, '0');
        return `${y}-${m}-${d}`;
    }

    // Numeric timestamp
    if (typeof dateValue === 'number') {
        return new Date(dateValue).toISOString().substring(0, 10);
    }

    return null;
}

// â”€â”€â”€ Helper: Get hours until departure â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Uses actual start time from booking, defaults to 21:00 for northern lights tours
function getHoursUntilDeparture(booking) {
    const productBooking = booking.productBookings?.[0];
    const tourDateStr = parseBokunDate(
        productBooking?.startDate || booking.startDate
    );
    if (!tourDateStr) return 999;

    // Try to get the actual start time (format: "21:00", "20:30", etc.)
    let startTimeStr = productBooking?.startTime
        || productBooking?.startTimeLocal
        || booking.startTime
        || null;

    // Parse the start time or default to 21:00 (evening tour)
    let hours = 21, minutes = 0;
    if (startTimeStr && typeof startTimeStr === 'string') {
        const timeParts = startTimeStr.match(/(\d{1,2}):(\d{2})/);
        if (timeParts) {
            hours = parseInt(timeParts[1], 10);
            minutes = parseInt(timeParts[2], 10);
        }
    }

    const departureDate = new Date(`${tourDateStr}T${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}:00`);
    const now = new Date();
    return (departureDate - now) / (1000 * 60 * 60);
}

// â”€â”€â”€ Helper: Normalize Bokun status â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function normalizeStatus(booking) {
    const raw = (booking.status || '').toUpperCase().trim();
    if (raw) return raw;

    // Fallback: check if booking is confirmed by other means
    if (booking.confirmed) return 'CONFIRMED';
    if (booking.cancelled) return 'CANCELLED';
    return 'CONFIRMED'; // Default for valid bookings
}

// â”€â”€â”€ Sanitize booking for customer view â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function sanitizeBookingForCustomer(booking) {
    const productBooking = booking.productBookings?.[0];
    const product = productBooking?.product;
    const activity = productBooking?.activity;

    // Check multiple possible pickup field paths
    const pickup = productBooking?.pickupPlace
        || productBooking?.pickupDropoffPlace
        || productBooking?.dropoffPickupPlace
        || productBooking?.fields?.pickupPlace
        || null;

    // Also check flatFields for pickup location name as fallback
    let pickupNameFromFlatFields = null;
    if (!pickup && productBooking?.flatFields) {
        const fields = productBooking.flatFields;
        pickupNameFromFlatFields = fields.pickupPlaceTitle
            || fields.pickupPlaceName
            || fields.pickupLocation
            || fields.pickup_place_title
            || null;
    }
    // Also try booking-level flatFields
    if (!pickup && !pickupNameFromFlatFields && booking.flatFields) {
        pickupNameFromFlatFields = booking.flatFields.pickupPlaceTitle
            || booking.flatFields.pickupPlaceName
            || booking.flatFields.pickupLocation
            || null;
    }

    // Build participant summary
    const participants = [];
    if (productBooking?.participants) {
        for (const p of productBooking.participants) {
            participants.push({
                type: p.category || p.pricingCategory?.ticketCategory || 'Guest',
                count: p.count || 1,
            });
        }
    }

    const totalGuests = productBooking?.totalParticipants ||
        participants.reduce((sum, p) => sum + p.count, 0) || 1;

    // Parse the date from multiple possible fields
    const tourDate = parseBokunDate(
        productBooking?.startDate ||
        productBooking?.date ||
        productBooking?.startDateLocal ||
        booking.startDate ||
        booking.date ||
        booking.startDateLocal ||
        booking.creationDate
    );

    // Normalize status
    const status = normalizeStatus(booking);

    // OTA detection
    const otaInfo = detectOTABooking(booking);

    return {
        bookingId: booking.id,
        confirmationCode: booking.confirmationCode,
        status,
        customerName: `${booking.customer?.firstName || ''} ${booking.customer?.lastName || ''}`.trim(),
        email: booking.customer?.email || '',
        tourName: product?.title || activity?.title || 'Northern Lights Tour',
        tourDate,
        startTime: productBooking?.startTime || productBooking?.startTimeLocal || null,
        totalGuests,
        participants,
        currentPickup: pickup ? {
            id: pickup.id,
            name: pickup.title || pickup.name || 'Not selected',
            address: pickup.address?.streetAddress || '',
        } : pickupNameFromFlatFields ? {
            id: null,
            name: pickupNameFromFlatFields,
            address: '',
        } : null,
        productId: product?.id || null,
        productBookingId: productBooking?.id || null,
        isOTA: otaInfo.isOTA,
        otaName: otaInfo.otaName,
        createdDate: booking.creationDate || null,
    };
}

// â”€â”€â”€ OTA Detection â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// "Backend", "Direct", and similar are NOT real OTAs â€” they are Bokun's
// channel names for direct/offline bookings.
const NON_OTA_CHANNELS = ['backend', 'direct', 'direct offline', 'direct online', 'website', 'manual', 'pos', 'bokun'];

function detectOTABooking(booking) {
    // Check affiliate/reseller first (these are always real OTAs)
    if (booking.affiliate?.title) {
        return { isOTA: true, otaName: booking.affiliate.title };
    }
    if (booking.reseller?.title) {
        return { isOTA: true, otaName: booking.reseller.title };
    }

    // Check channel â€” but filter out non-OTA channels
    const channelTitle = booking.channel?.title || '';
    if (channelTitle && !NON_OTA_CHANNELS.includes(channelTitle.toLowerCase().trim())) {
        return { isOTA: true, otaName: channelTitle };
    }

    return { isOTA: false, otaName: null };
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// 1. PORTAL LOOKUP BOOKING
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
const portalLookupBooking = onRequest(
    {
        cors: true,
        invoker: 'public',
        secrets: ['BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY'],
    },
    async (req, res) => {
        if (req.method !== 'POST') {
            res.status(405).json({ error: 'Method not allowed' });
            return;
        }

        // Rate limit
        const clientIp = req.headers['x-forwarded-for'] || req.ip || 'unknown';
        if (isRateLimited(clientIp)) {
            res.status(429).json({ error: 'Too many requests. Please try again in a minute.' });
            return;
        }

        const { name, email, confirmationCode } = req.body;

        const accessKey = process.env.BOKUN_ACCESS_KEY;
        const secretKey = process.env.BOKUN_SECRET_KEY;

        if (!accessKey || !secretKey) {
            res.status(500).json({ error: 'Service temporarily unavailable' });
            return;
        }

        try {
            console.log(`🔍 Portal lookup: ${confirmationCode}${email ? ` by ${email}` : ' (code-only)'}`);

            const { booking, error } = await verifyAndFetchBooking(
                confirmationCode, email, name, accessKey, secretKey
            );

            if (error) {
                res.status(404).json({ error });
                return;
            }

            const sanitized = sanitizeBookingForCustomer(booking);

            // Check if booking is in a modifiable state
            const status = normalizeStatus(booking);
            const modifiable = ['CONFIRMED', 'AMENDED'].includes(status);
            const isCancelled = status === 'CANCELLED';

            // Check if tour date is in the past
            const tourDate = new Date(sanitized.tourDate);
            const now = new Date();
            const isPast = tourDate < new Date(now.toISOString().split('T')[0]);

            // Calculate hours until departure using actual start time
            const hoursUntilDeparture = getHoursUntilDeparture(booking);
            const isWithin24hRaw = hoursUntilDeparture < 24;
            const isWithin2h = hoursUntilDeparture < 2;

            // Check if tour is cancelled due to weather â€” if so, allow reschedule within 24h
            let tourCancelled = false;
            if (sanitized.tourDate) {
                tourCancelled = await isTourCancelledForDate(sanitized.tourDate);
            }

            // Determine cancel policy
            // OFF + within 24h = weather_cancelled (courtesy reschedule vs original tour refund)
            // ON/not set + within 24h = non_refundable (resources allocated, no refund)
            // Otherwise = normal
            let cancelPolicy = 'normal';
            if (isWithin24hRaw && tourCancelled) {
                cancelPolicy = 'weather_cancelled';
            } else if (isWithin24hRaw) {
                cancelPolicy = 'non_refundable';
            }

            // Check OTA
            const otaInfo = detectOTABooking(booking);

            res.json({
                success: true,
                booking: sanitized,
                canModify: modifiable && !isPast && (!isWithin24hRaw || tourCancelled),
                canCancel: modifiable && !isPast,
                canChangePickup: modifiable && !isPast && !isWithin2h,
                cancelPolicy,
                isWithin24h: isWithin24hRaw,
                isWithin2h,
                tourCancelledByWeather: tourCancelled,
                isPastBooking: isPast,
                isCancelled,
                isOTA: otaInfo.isOTA,
                otaName: otaInfo.otaName,
                otaMessage: otaInfo.isOTA
                    ? `This booking was made through ${otaInfo.otaName}. You can still reschedule or change your pickup here.`
                    : null,
            });

        } catch (error) {
            console.error('âŒ Portal lookup error:', error.message);
            res.status(500).json({ error: 'Unable to look up your booking. Please try again later.' });
        }
    }
);

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// 2. PORTAL CHECK AVAILABILITY
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
const portalCheckAvailability = onRequest(
    {
        cors: true,
        invoker: 'public',
        secrets: ['BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY', 'BOKUN_OCTO_TOKEN'],
    },
    async (req, res) => {
        if (req.method !== 'POST') {
            res.status(405).json({ error: 'Method not allowed' });
            return;
        }

        const clientIp = req.headers['x-forwarded-for'] || req.ip || 'unknown';
        if (isRateLimited(clientIp)) {
            res.status(429).json({ error: 'Too many requests. Please try again in a minute.' });
            return;
        }

        const { confirmationCode, email, name, targetDate } = req.body;

        if (!targetDate) {
            res.status(400).json({ error: 'Please select a date' });
            return;
        }

        const accessKey = process.env.BOKUN_ACCESS_KEY;
        const secretKey = process.env.BOKUN_SECRET_KEY;
        const octoToken = process.env.BOKUN_OCTO_TOKEN;

        if (!accessKey || !secretKey || !octoToken) {
            res.status(500).json({ error: 'Service temporarily unavailable' });
            return;
        }

        try {
            // Re-verify identity
            const { booking, error } = await verifyAndFetchBooking(
                confirmationCode, email, name, accessKey, secretKey
            );

            if (error) {
                res.status(404).json({ error });
                return;
            }

            // Check 24h restriction using actual departure time
            const hoursUntilDeparture = getHoursUntilDeparture(booking);
            if (hoursUntilDeparture < 24) {
                const tourDateStr = parseBokunDate(booking.productBookings?.[0]?.startDate || booking.startDate);
                const isCancelledByWeather = tourDateStr ? await isTourCancelledForDate(tourDateStr) : false;
                if (!isCancelledByWeather) {
                    res.status(400).json({
                        error: 'Your tour is less than 24 hours away. Non-refundable resources have already been allocated for your booking. Please email us at info@auroraviking.com for any last-minute changes.'
                    });
                    return;
                }
                console.log('\u{1F327}\uFE0F Tour cancelled for weather \u2014 allowing availability check within 24h');
            }

            const productBooking = booking.productBookings?.[0];
            const productId = productBooking?.product?.id;

            if (!productId) {
                res.status(400).json({ error: 'Unable to check availability for this booking type' });
                return;
            }

            // OCTO helper
            const octoRequest = (method, path, body) => {
                return new Promise((resolve, reject) => {
                    const bodyStr = body ? JSON.stringify(body) : null;
                    const opts = {
                        hostname: 'api.bokun.io',
                        path: `/octo/v1${path}`,
                        method,
                        headers: {
                            'Content-Type': 'application/json',
                            'Authorization': `Bearer ${octoToken}`,
                        },
                    };
                    if (bodyStr) opts.headers['Content-Length'] = Buffer.byteLength(bodyStr);

                    const apiReq = https.request(opts, (apiRes) => {
                        let data = '';
                        apiRes.on('data', (chunk) => { data += chunk; });
                        apiRes.on('end', () => {
                            if (apiRes.statusCode >= 200 && apiRes.statusCode < 300) {
                                try { resolve(JSON.parse(data)); } catch (e) { resolve(data); }
                            } else { reject(new Error(`OCTO ${apiRes.statusCode}: ${data.substring(0, 200)}`)); }
                        });
                    });
                    apiReq.on('error', reject);
                    if (bodyStr) apiReq.write(bodyStr);
                    apiReq.end();
                });
            };

            // Get correct OCTO product + option IDs (same approach as booking_management.js)
            let octoProductId = String(productId);
            let octoOptionId = String(productBooking?.activity?.id || productId);

            try {
                const octoProducts = await octoRequest('GET', '/products');
                if (Array.isArray(octoProducts) && octoProducts.length > 0) {
                    const matchingProduct = octoProducts.find(p => String(p.id) === String(productId));
                    if (matchingProduct) {
                        octoProductId = String(matchingProduct.id);
                        if (matchingProduct.options?.length > 0) {
                            octoOptionId = String(matchingProduct.options[0].id);
                        }
                    } else if (octoProducts[0]) {
                        octoProductId = String(octoProducts[0].id);
                        if (octoProducts[0].options?.length > 0) {
                            octoOptionId = String(octoProducts[0].options[0].id);
                        }
                    }
                }
            } catch (e) {
                console.log(`âš ï¸ Could not fetch OCTO products: ${e.message}`);
            }

            console.log(`ðŸ“… Portal availability check: product ${octoProductId}, option ${octoOptionId}, date ${targetDate}`);

            // Check OCTO availability
            let availabilityResult;
            try {
                availabilityResult = await octoRequest('POST', '/availability', {
                    productId: octoProductId,
                    optionId: octoOptionId,
                    localDate: targetDate,
                });
            } catch (e) {
                console.log(`âš ï¸ OCTO availability check failed: ${e.message}`);
                availabilityResult = [];
            }

            const slots = (Array.isArray(availabilityResult) ? availabilityResult : []).map(slot => ({
                id: slot.id,
                localDateTimeStart: slot.localDateTimeStart,
                localDateTimeEnd: slot.localDateTimeEnd,
                available: slot.available,
                status: slot.status,
                vacancies: slot.vacancies,
            }));

            const hasAvailability = slots.some(s => s.available !== false && s.status !== 'SOLD_OUT');

            res.json({
                success: true,
                targetDate,
                available: hasAvailability,
                slots,
                message: hasAvailability
                    ? 'Availability confirmed for this date!'
                    : 'Sorry, this date is fully booked. Please try another date.',
            });

        } catch (error) {
            console.error('âŒ Portal availability check error:', error.message);
            res.status(500).json({ error: 'Unable to check availability. Please try again later.' });
        }
    }
);

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// 3. PORTAL RESCHEDULE BOOKING
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
const portalRescheduleBooking = onRequest(
    {
        cors: true,
        invoker: 'public',
        secrets: ['BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY'],
    },
    async (req, res) => {
        if (req.method !== 'POST') {
            res.status(405).json({ error: 'Method not allowed' });
            return;
        }

        const clientIp = req.headers['x-forwarded-for'] || req.ip || 'unknown';
        if (isRateLimited(clientIp)) {
            res.status(429).json({ error: 'Too many requests. Please try again in a minute.' });
            return;
        }

        const { confirmationCode, email, name, newDate } = req.body;

        if (!newDate) {
            res.status(400).json({ error: 'Please select a new date' });
            return;
        }

        const accessKey = process.env.BOKUN_ACCESS_KEY;
        const secretKey = process.env.BOKUN_SECRET_KEY;

        if (!accessKey || !secretKey) {
            res.status(500).json({ error: 'Service temporarily unavailable' });
            return;
        }

        try {
            // Verify identity
            const { booking, error } = await verifyAndFetchBooking(
                confirmationCode, email, name, accessKey, secretKey
            );

            if (error) {
                res.status(404).json({ error });
                return;
            }

            // Note: OTA bookings CAN be rescheduled via ActivityChangeDateAction
            // (same internal API Bokun uses in their UI)
            const otaInfo = detectOTABooking(booking);

            // Check 24h restriction using actual departure time
            const hoursUntilDeparture = getHoursUntilDeparture(booking);
            if (hoursUntilDeparture < 24) {
                const tourDateStr = parseBokunDate(booking.productBookings?.[0]?.startDate || booking.startDate);
                const isCancelledByWeather = tourDateStr ? await isTourCancelledForDate(tourDateStr) : false;
                if (!isCancelledByWeather) {
                    res.status(400).json({
                        error: 'Your tour is less than 24 hours away. Non-refundable resources have already been allocated for your booking. Please email us at info@auroraviking.com for any last-minute changes.'
                    });
                    return;
                }
                console.log('🌧️ Tour cancelled for weather — allowing reschedule within 24h');
            }

            // Check booking status
            const rescheduleStatus = normalizeStatus(booking);
            if (!['CONFIRMED', 'AMENDED'].includes(rescheduleStatus)) {
                res.status(400).json({ error: 'This booking cannot be rescheduled due to its current status.' });
                return;
            }

            const customerName = `${booking.customer?.firstName || ''} ${booking.customer?.lastName || ''}`.trim();
            const productBooking = booking.productBookings?.[0];
            const activityBookingId = productBooking?.id;

            console.log(`📅 Portal reschedule: ${booking.confirmationCode} → ${newDate} by ${customerName} (OTA: ${otaInfo.isOTA ? otaInfo.otaName : 'no'})`);

            // Use ActivityChangeDateAction — works for ALL bookings including OTA
            if (activityBookingId) {
                try {
                    const crypto = require('crypto');
                    const https = require('https');
                    const editPath = '/booking.json/edit';
                    const editDate = new Date().toISOString().replace('T', ' ').substring(0, 19);
                    const editMessage = editDate + accessKey + 'POST' + editPath;
                    const editSignature = crypto.createHmac('sha1', secretKey).update(editMessage).digest('base64');

                    // Get startTimeId from original booking if available
                    const startTimeId = productBooking?.startTimeId;

                    const changeDateActions = [{
                        type: 'ActivityChangeDateAction',
                        activityBookingId: parseInt(activityBookingId),
                        date: newDate,
                        ...(startTimeId && { startTimeId: parseInt(startTimeId) }),
                    }];

                    console.log(`📅 ActivityChangeDateAction: activity ${activityBookingId} → ${newDate}`);

                    const apiResult = await new Promise((resolve, reject) => {
                        const editBody = JSON.stringify(changeDateActions);
                        const options = {
                            hostname: 'api.bokun.io',
                            path: editPath,
                            method: 'POST',
                            headers: {
                                'Content-Type': 'application/json;charset=UTF-8',
                                'Content-Length': Buffer.byteLength(editBody),
                                'X-Bokun-AccessKey': accessKey,
                                'X-Bokun-Date': editDate,
                                'X-Bokun-Signature': editSignature,
                            },
                        };

                        const apiReq = https.request(options, (apiRes) => {
                            let data = '';
                            apiRes.on('data', (chunk) => { data += chunk; });
                            apiRes.on('end', () => {
                                console.log(`📅 ActivityChangeDateAction response: ${apiRes.statusCode}`);
                                if (apiRes.statusCode >= 200 && apiRes.statusCode < 400) {
                                    resolve({ success: true, data });
                                } else {
                                    reject(new Error(`ActivityChangeDateAction failed: ${apiRes.statusCode} - ${data}`));
                                }
                            });
                        });
                        apiReq.on('error', reject);
                        apiReq.write(editBody);
                        apiReq.end();
                    });

                    console.log(`✅ Reschedule succeeded via ActivityChangeDateAction!`);

                    // Record in reschedule_requests so getBookingManifest picks it up
                    const originalDate = parseBokunDate(productBooking?.startDate || booking.startDate);
                    await db.collection('reschedule_requests').add({
                        bookingId: String(booking.id),
                        confirmationCode: booking.confirmationCode,
                        newDate,
                        originalDate,
                        reason: 'Customer self-service reschedule via portal',
                        userId: 'customer_portal',
                        source: 'customer_portal',
                        customerName,
                        customerEmail: email,
                        status: 'completed',
                        method: 'activity_change_date_action',
                        isOTABooking: otaInfo.isOTA,
                        otaName: otaInfo.otaName || null,
                        createdAt: admin.firestore.FieldValue.serverTimestamp(),
                        completedAt: admin.firestore.FieldValue.serverTimestamp(),
                    });

                    // Log the action
                    await db.collection('booking_actions').add({
                        bookingId: String(booking.id),
                        confirmationCode: booking.confirmationCode,
                        customerName,
                        action: 'reschedule',
                        performedBy: 'customer_portal',
                        performedAt: admin.firestore.FieldValue.serverTimestamp(),
                        reason: 'Customer self-service reschedule via portal',
                        originalData: { date: originalDate },
                        newData: { date: newDate },
                        success: true,
                        method: 'activity_change_date_action',
                        isOTABooking: otaInfo.isOTA,
                        otaName: otaInfo.otaName || null,
                    });

                    // Notify admins
                    await sendNotificationToAdminsOnly(
                        '📅 Customer Rescheduled',
                        `${customerName} rescheduled booking ${booking.confirmationCode} to ${newDate}${otaInfo.isOTA ? ` (${otaInfo.otaName})` : ''}`,
                        {
                            type: 'portal_reschedule',
                            bookingId: String(booking.id),
                            confirmationCode: booking.confirmationCode,
                        }
                    );

                    res.json({
                        success: true,
                        message: `Your booking has been rescheduled to ${newDate}. You will receive a confirmation shortly.`,
                    });
                    return;

                } catch (changeDateError) {
                    console.error(`❌ ActivityChangeDateAction failed: ${changeDateError.message}`);
                    // Fall through to queue-based approach
                }
            }

            // Fallback: Write to reschedule_requests queue (trigger will process)
            console.log(`⚠️ Falling back to reschedule_requests queue for ${booking.confirmationCode}`);
            const requestRef = await db.collection('reschedule_requests').add({
                bookingId: String(booking.id),
                confirmationCode: booking.confirmationCode,
                newDate,
                reason: 'Customer self-service reschedule via portal',
                userId: 'customer_portal',
                source: 'customer_portal',
                customerName,
                customerEmail: email,
                status: 'pending',
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // Notify admins
            await sendNotificationToAdminsOnly(
                '📅 Customer Rescheduled (pending)',
                `${customerName} rescheduled booking ${booking.confirmationCode} to ${newDate} — needs manual processing`,
                {
                    type: 'portal_reschedule',
                    bookingId: String(booking.id),
                    confirmationCode: booking.confirmationCode,
                }
            );

            res.json({
                success: true,
                requestId: requestRef.id,
                message: `Your booking has been submitted for rescheduling to ${newDate}. You will receive a confirmation email shortly.`,
            });

        } catch (error) {
            console.error('âŒ Portal reschedule error:', error.message);
            res.status(500).json({ error: 'Unable to process your reschedule request. Please try again or contact us at info@auroraviking.com' });
        }
    }
);

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// 4. PORTAL CANCEL BOOKING
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
const portalCancelBooking = onRequest(
    {
        cors: true,
        invoker: 'public',
        secrets: ['BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY'],
    },
    async (req, res) => {
        if (req.method !== 'POST') {
            res.status(405).json({ error: 'Method not allowed' });
            return;
        }

        const clientIp = req.headers['x-forwarded-for'] || req.ip || 'unknown';
        if (isRateLimited(clientIp)) {
            res.status(429).json({ error: 'Too many requests. Please try again in a minute.' });
            return;
        }

        const { confirmationCode, email, name, reason } = req.body;

        const accessKey = process.env.BOKUN_ACCESS_KEY;
        const secretKey = process.env.BOKUN_SECRET_KEY;

        if (!accessKey || !secretKey) {
            res.status(500).json({ error: 'Service temporarily unavailable' });
            return;
        }

        try {
            // Verify identity
            const { booking, error } = await verifyAndFetchBooking(
                confirmationCode, email, name, accessKey, secretKey
            );

            if (error) {
                res.status(404).json({ error });
                return;
            }

            // Check booking status
            const cancelStatus = normalizeStatus(booking);
            if (!['CONFIRMED', 'AMENDED'].includes(cancelStatus)) {
                res.status(400).json({ error: 'This booking cannot be cancelled due to its current status.' });
                return;
            }

            // Determine cancel policy context
            const hoursUntilCancelDeparture = getHoursUntilDeparture(booking);
            const cancelTourDateStr = parseBokunDate(booking.productBookings?.[0]?.startDate || booking.startDate);
            const isTourOff = cancelTourDateStr ? await isTourCancelledForDate(cancelTourDateStr) : false;
            let cancelPolicyApplied = 'normal';
            if (hoursUntilCancelDeparture < 24 && isTourOff) {
                cancelPolicyApplied = 'weather_cancelled';
            } else if (hoursUntilCancelDeparture < 24) {
                cancelPolicyApplied = 'non_refundable';
            }

            const customerName = `${booking.customer?.firstName || ''} ${booking.customer?.lastName || ''}`.trim();
            const tourDate = booking.productBookings?.[0]?.startDate || booking.startDate;
            const totalGuests = booking.productBookings?.[0]?.totalParticipants || 1;
            const tourName = booking.productBookings?.[0]?.product?.title || 'Northern Lights Tour';

            console.log(`ðŸ—‘ï¸ Portal cancel: ${booking.confirmationCode} by ${customerName}`);

            // Write to cancel_requests (existing trigger will process)
            const cancelRef = await db.collection('cancel_requests').add({
                bookingId: String(booking.id),
                confirmationCode: booking.confirmationCode,
                reason: reason || 'Customer self-service cancellation via portal',
                userId: 'customer_portal',
                source: 'customer_portal',
                customerName,
                customerEmail: email,
                cancelPolicy: cancelPolicyApplied,
                isWithin24h: hoursUntilCancelDeparture < 24,
                isTourOff,
                status: 'pending',
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // Write to portal_cancellations for admin refund review
            await db.collection('portal_cancellations').add({
                bookingId: String(booking.id),
                confirmationCode: booking.confirmationCode,
                customerName,
                customerEmail: email,
                tourName,
                tourDate,
                totalGuests,
                reason: reason || 'No reason provided',
                cancelRequestId: cancelRef.id,
                cancelPolicy: cancelPolicyApplied,
                isWithin24h: hoursUntilCancelDeparture < 24,
                isTourOff,
                refundEligible: cancelPolicyApplied === 'normal' || cancelPolicyApplied === 'weather_cancelled',
                status: 'pending_review',
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // Notify admins
            await sendNotificationToAdminsOnly(
                'ðŸ—‘ï¸ Customer Cancelled Booking',
                `${customerName} cancelled booking ${booking.confirmationCode} (${tourDate}, ${totalGuests} guests). Review for refund.`,
                {
                    type: 'portal_cancellation',
                    bookingId: String(booking.id),
                    confirmationCode: booking.confirmationCode,
                }
            );

            res.json({
                success: true,
                requestId: cancelRef.id,
                message: 'Your booking has been cancelled. If you are eligible for a refund, our team will be in touch within 2-3 business days.',
            });

        } catch (error) {
            console.error('âŒ Portal cancel error:', error.message);
            res.status(500).json({ error: 'Unable to process your cancellation. Please try again or contact us at info@auroraviking.com' });
        }
    }
);

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// 5. PORTAL GET PICKUP PLACES
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
const portalGetPickupPlaces = onRequest(
    {
        cors: true,
        invoker: 'public',
        secrets: ['BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY'],
    },
    async (req, res) => {
        if (req.method !== 'GET' && req.method !== 'POST') {
            res.status(405).json({ error: 'Method not allowed' });
            return;
        }

        const clientIp = req.headers['x-forwarded-for'] || req.ip || 'unknown';
        if (isRateLimited(clientIp)) {
            res.status(429).json({ error: 'Too many requests.' });
            return;
        }

        const confirmationCode = req.query.confirmationCode || req.body?.confirmationCode;
        const email = req.query.email || req.body?.email;
        const name = req.query.name || req.body?.name;
        const productId = req.query.productId || req.body?.productId;

        if (!productId) {
            res.status(400).json({ error: 'Product information missing' });
            return;
        }

        const accessKey = process.env.BOKUN_ACCESS_KEY;
        const secretKey = process.env.BOKUN_SECRET_KEY;

        if (!accessKey || !secretKey) {
            res.status(500).json({ error: 'Service temporarily unavailable' });
            return;
        }

        try {
            // Verify identity
            const { booking, error } = await verifyAndFetchBooking(
                confirmationCode, email, name, accessKey, secretKey
            );

            if (error) {
                res.status(404).json({ error });
                return;
            }

            console.log(`ðŸ“ Portal pickup places for product ${productId}`);

            const pickupPath = `/activity.json/${productId}/pickup-places`;
            const pickupDate = new Date().toISOString().replace('T', ' ').substring(0, 19);
            const pickupMessage = pickupDate + accessKey + 'GET' + pickupPath;
            const pickupSignature = crypto.createHmac('sha1', secretKey).update(pickupMessage).digest('base64');

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
                                resolve(parsed.pickupPlaces || parsed.pickupDropoffPlaces || parsed.items || parsed);
                            } catch (e) { resolve([]); }
                        } else { resolve([]); }
                    });
                });
                apiReq.on('error', () => resolve([]));
                apiReq.end();
            });

            const places = (Array.isArray(pickupPlaces) ? pickupPlaces : []).map(place => ({
                id: place.id,
                title: place.title || place.name,
                address: place.address?.streetAddress || place.address || '',
                city: place.address?.city || '',
                type: place.type || 'HOTEL',
            }));

            res.json({ success: true, pickupPlaces: places });

        } catch (error) {
            console.error('âŒ Portal pickup places error:', error.message);
            res.status(500).json({ error: 'Unable to load pickup locations. Please try again.' });
        }
    }
);

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// 6. PORTAL UPDATE PICKUP
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
const portalUpdatePickup = onRequest(
    {
        cors: true,
        invoker: 'public',
        secrets: ['BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY'],
    },
    async (req, res) => {
        if (req.method !== 'POST') {
            res.status(405).json({ error: 'Method not allowed' });
            return;
        }

        const clientIp = req.headers['x-forwarded-for'] || req.ip || 'unknown';
        if (isRateLimited(clientIp)) {
            res.status(429).json({ error: 'Too many requests.' });
            return;
        }

        const { confirmationCode, email, name, pickupPlaceId, pickupPlaceName } = req.body;

        if (!pickupPlaceId) {
            res.status(400).json({ error: 'Please select a pickup location' });
            return;
        }

        const accessKey = process.env.BOKUN_ACCESS_KEY;
        const secretKey = process.env.BOKUN_SECRET_KEY;

        if (!accessKey || !secretKey) {
            res.status(500).json({ error: 'Service temporarily unavailable' });
            return;
        }

        try {
            // Verify identity
            const { booking, error } = await verifyAndFetchBooking(
                confirmationCode, email, name, accessKey, secretKey
            );

            if (error) {
                res.status(404).json({ error });
                return;
            }

            // Check booking status
            const pickupStatus = normalizeStatus(booking);
            if (!['CONFIRMED', 'AMENDED'].includes(pickupStatus)) {
                res.status(400).json({ error: 'This booking cannot be modified due to its current status.' });
                return;
            }

            // Check 2h restriction for pickup changes
            const hoursUntilPickupDeparture = getHoursUntilDeparture(booking);
            if (hoursUntilPickupDeparture < 2) {
                res.status(400).json({
                    error: 'Pickup location changes are not available within 2 hours of departure. Please email us at info@auroraviking.com.'
                });
                return;
            }

            // Check OTA
            const otaInfo = detectOTABooking(booking);
            if (otaInfo.isOTA) {
                res.status(400).json({
                    error: `This booking was made through ${otaInfo.otaName}. Please contact ${otaInfo.otaName} directly to make changes.`
                });
                return;
            }

            const customerName = `${booking.customer?.firstName || ''} ${booking.customer?.lastName || ''}`.trim();
            const productBookingId = booking.productBookings?.[0]?.id;

            console.log(`ðŸ“ Portal pickup update: ${booking.confirmationCode} â†’ ${pickupPlaceName || pickupPlaceId}`);

            // Write to pickup_update_requests (existing trigger will process)
            const requestRef = await db.collection('pickup_update_requests').add({
                bookingId: String(booking.id),
                productBookingId: productBookingId ? String(productBookingId) : null,
                pickupPlaceId: String(pickupPlaceId),
                pickupPlaceName: pickupPlaceName || '',
                userId: 'customer_portal',
                source: 'customer_portal',
                customerName,
                customerEmail: email,
                status: 'pending',
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // Notify admins
            await sendNotificationToAdminsOnly(
                'ðŸ“ Customer Changed Pickup',
                `${customerName} changed pickup for ${booking.confirmationCode} to ${pickupPlaceName || pickupPlaceId}`,
                {
                    type: 'portal_pickup_change',
                    bookingId: String(booking.id),
                    confirmationCode: booking.confirmationCode,
                }
            );

            res.json({
                success: true,
                requestId: requestRef.id,
                message: `Your pickup location has been updated to ${pickupPlaceName || 'the selected location'}. You will receive a confirmation email shortly.`,
            });

        } catch (error) {
            console.error('âŒ Portal pickup update error:', error.message);
            res.status(500).json({ error: 'Unable to update your pickup location. Please try again or contact us at info@auroraviking.com' });
        }
    }
);

// =====================================================================
// 7. BOOKING MANIFEST (Admin only - fetches all bookings + portal activity)
// =====================================================================
const getBookingManifest = onCall(
    {
        region: 'us-central1',
        timeoutSeconds: 30,
    },
    async (request) => {
        if (!request.auth) {
            throw new Error('You must be logged in to view the booking manifest');
        }

        const { date } = request.data || {};
        if (!date) throw new Error('Date is required');

        console.log('Fetching booking manifest for ' + date);

        // 1. Fetch bookings from cached_bookings (same source as pickup menu)
        let bookings = [];
        try {
            const cachedDoc = await db.collection('cached_bookings').doc(date).get();
            if (cachedDoc.exists) {
                const data = cachedDoc.data();
                bookings = data.bookings || [];
                console.log('Found ' + bookings.length + ' cached bookings for ' + date);
            } else {
                console.log('No cached bookings found for ' + date);
            }

            // Also merge manual bookings
            const manualSnap = await db.collection('manual_bookings')
                .where('date', '==', date)
                .get();
            manualSnap.docs.forEach(doc => {
                const manual = doc.data().booking;
                if (manual) bookings.push(manual);
            });
        } catch (e) {
            console.error('Failed to fetch cached bookings:', e.message);
            throw new Error('Failed to fetch bookings');
        }

        console.log('Total bookings for ' + date + ': ' + bookings.length);

        // Helper: safely extract YYYY-MM-DD from various date formats
        function safeExtractDate(val) {
            if (!val) return '';
            if (typeof val === 'string') return val.substring(0, 10);
            if (val.toDate) return val.toDate().toISOString().substring(0, 10);
            if (val.year) {
                const m = String(val.month || val.monthOfYear || 1).padStart(2, '0');
                const d = String(val.day || val.dayOfMonth || 1).padStart(2, '0');
                return val.year + '-' + m + '-' + d;
            }
            return String(val).substring(0, 10);
        }


        // 2. Get tour status for this date
        let tourStatus = 'UNKNOWN';
        try {
            const statusDoc = await db.collection('tour_status').doc(date).get();
            if (statusDoc.exists) {
                tourStatus = statusDoc.data().status; // 'ON', 'OFF'
            }
        } catch (e) {
            console.log('Could not get tour status:', e.message);
        }

        // 3. Get all portal cancellations for this date
        const cancelSnap = await db.collection('portal_cancellations')
            .orderBy('createdAt', 'desc')
            .limit(500)
            .get();
        const cancellations = {};
        cancelSnap.docs.forEach(doc => {
            const data = doc.data();
            // Match by confirmation code
            if (data.confirmationCode) {
                cancellations[data.confirmationCode] = {
                    docId: doc.id,
                    ...data,
                };
            }
        });

        // 4. Get all reschedule requests for this date
        const rescheduleSnap = await db.collection('reschedule_requests')
            .orderBy('createdAt', 'desc')
            .limit(500)
            .get();
        const reschedules = {};
        rescheduleSnap.docs.forEach(doc => {
            const data = doc.data();
            const origDate = safeExtractDate(data.originalDate);
            if (data.confirmationCode && origDate === date) {
                reschedules[data.confirmationCode] = {
                    docId: doc.id,
                    ...data,
                    newDate: safeExtractDate(data.newDate) || data.newDate,
                };
            }
        });

        // 5. Build manifest entries
        const manifest = bookings.map(booking => {
            // Support both cached_bookings fields (flat) and Bokun API fields (nested)
            const customerName = booking.customerFullName ||
                ((booking.customer?.firstName || '') + ' ' + (booking.customer?.lastName || '')).trim() ||
                'Unknown';
            const confirmationCode = booking.confirmationCode || '';
            const email = booking.email || booking.customer?.email || '';
            const guests = booking.numberOfGuests || booking.totalParticipants || 1;
            const tourName = booking.productTitle || 'Northern Lights Tour';

            // Determine status
            let status = 'as_scheduled'; // default
            let statusLabel = 'As Scheduled';
            let refundStatus = null;
            let refundDocId = null;
            let reviewedBy = null;
            let newDate = null;
            let cancelReason = null;

            // Check if rescheduled
            const reschedule = reschedules[confirmationCode];
            if (reschedule) {
                status = 'rescheduled';
                newDate = reschedule.newDate || 'unknown';
                statusLabel = `Rescheduled to ${newDate}`;
            }

            // Check if cancelled (overrides reschedule if both exist)
            const cancellation = cancellations[confirmationCode];
            if (cancellation) {
                status = 'cancelled';
                statusLabel = 'Cancelled';
                cancelReason = cancellation.reason || '';
                refundStatus = cancellation.status || 'pending_review';
                refundDocId = cancellation.docId;
                reviewedBy = cancellation.reviewedByName || null;
            }

            // If tour is OFF and no action taken, mark as disrupted
            if (tourStatus === 'OFF' && status === 'as_scheduled') {
                status = 'disrupted';
                statusLabel = 'Disrupted, No Actions Taken';
            }

            return {
                customerName,
                confirmationCode,
                email,
                guests,
                tourName,
                status,
                statusLabel,
                refundStatus,
                refundDocId,
                reviewedBy,
                newDate,
                cancelReason,
            };
        });

        return {
            date,
            tourStatus,
            totalBookings: manifest.length,
            manifest,
            summary: {
                asScheduled: manifest.filter(m => m.status === 'as_scheduled').length,
                disrupted: manifest.filter(m => m.status === 'disrupted').length,
                rescheduled: manifest.filter(m => m.status === 'rescheduled').length,
                cancelled: manifest.filter(m => m.status === 'cancelled').length,
            },
        };
    }
);

// Export all portal functions
module.exports = {
    portalLookupBooking,
    portalCheckAvailability,
    portalRescheduleBooking,
    portalCancelBooking,
    portalGetPickupPlaces,
    portalUpdatePickup,
    getBookingManifest,
};
