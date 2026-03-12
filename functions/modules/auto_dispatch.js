/**
 * Auto-Dispatch Module
 * Server-side automated pickup distribution
 * 
 * Triggers:
 * 1. Scheduled every 5 minutes: checks if auto-dispatch needed
 *    - At noon: auto-accepts top-ranked applied guides
 *    - 30 min before pickup: distributes bookings + assigns buses
 *    - 10 min before pickup: handles last-minute unassigned bookings
 */
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall } = require('firebase-functions/v2/https');
const { db } = require('../utils/firebase');
const { sendNotificationToAdminsOnly } = require('../utils/notifications');

// ============================================
// CORE LOGIC
// ============================================

/**
 * Calculate how many guides are needed for a passenger count.
 * Formula: ceil(totalPax / 18) — 19-seat bus with 1 buffer for guide.
 */
function calculateGuidesNeeded(totalPassengers) {
    if (totalPassengers <= 0) return 0;
    return Math.ceil(totalPassengers / 18);
}

/**
 * Format date as YYYY-MM-DD string (Iceland timezone)
 */
function getTodayDateStr() {
    const now = new Date();
    const iceland = new Date(now.toLocaleString('en-US', { timeZone: 'Atlantic/Reykjavik' }));
    return `${iceland.getFullYear()}-${String(iceland.getMonth() + 1).padStart(2, '0')}-${String(iceland.getDate()).padStart(2, '0')}`;
}

/**
 * Get current hour in Iceland timezone
 */
function getIcelandHour() {
    const now = new Date();
    const iceland = new Date(now.toLocaleString('en-US', { timeZone: 'Atlantic/Reykjavik' }));
    return iceland.getHours();
}

/**
 * Get current time in Iceland as minutes since midnight
 */
function getIcelandMinutesSinceMidnight() {
    const now = new Date();
    const iceland = new Date(now.toLocaleString('en-US', { timeZone: 'Atlantic/Reykjavik' }));
    return iceland.getHours() * 60 + iceland.getMinutes();
}

/**
 * Get bookings for today from cached_bookings
 */
async function getTodayBookings(dateStr) {
    const doc = await db.collection('cached_bookings').doc(dateStr).get();
    if (!doc.exists) return [];
    return doc.data().bookings || [];
}

/**
 * Get total passenger count from bookings
 */
function getTotalPassengers(bookings) {
    return bookings.reduce((sum, b) => {
        return sum + (b.totalParticipants || b.numberOfGuests || 0);
    }, 0);
}

/**
 * Get earliest pickup time as minutes since midnight
 */
function getEarliestPickupMinutes(bookings) {
    let earliest = Infinity;
    for (const booking of bookings) {
        if (booking.pickupTime) {
            let minutes;
            if (typeof booking.pickupTime === 'string' && booking.pickupTime.includes(':')) {
                const parts = booking.pickupTime.split(':');
                minutes = parseInt(parts[0]) * 60 + parseInt(parts[1]);
            } else if (typeof booking.pickupTime === 'string') {
                // ISO date string
                const d = new Date(booking.pickupTime);
                minutes = d.getHours() * 60 + d.getMinutes();
            }
            if (minutes !== undefined && minutes < earliest) {
                earliest = minutes;
            }
        }
    }
    return earliest === Infinity ? null : earliest;
}

/**
 * Get guides with APPLIED (pending) shifts for a date, sorted by priority descending
 */
async function getAppliedGuides(dateStr) {
    const shiftsSnapshot = await db.collection('shifts')
        .where('date', '==', dateStr)
        .where('status', '==', 'applied')
        .get();

    if (shiftsSnapshot.empty) return [];

    const guidesWithShifts = [];
    for (const shiftDoc of shiftsSnapshot.docs) {
        const shift = shiftDoc.data();
        const guideId = shift.guideId;
        if (!guideId) continue;

        const userDoc = await db.collection('users').doc(guideId).get();
        if (!userDoc.exists) continue;

        const userData = userDoc.data();
        guidesWithShifts.push({
            guideId,
            guideName: userData.fullName || 'Unknown',
            priority: userData.priority || 0,
            shiftId: shiftDoc.id,
        });
    }

    // Sort by priority descending
    guidesWithShifts.sort((a, b) => b.priority - a.priority);
    return guidesWithShifts;
}

/**
 * Get guides with ACCEPTED shifts for a date, sorted by priority descending
 */
async function getAcceptedGuides(dateStr) {
    const shiftsSnapshot = await db.collection('shifts')
        .where('date', '==', dateStr)
        .where('status', '==', 'accepted')
        .get();

    if (shiftsSnapshot.empty) return [];

    const guides = [];
    for (const shiftDoc of shiftsSnapshot.docs) {
        const shift = shiftDoc.data();
        const guideId = shift.guideId;
        if (!guideId) continue;

        const userDoc = await db.collection('users').doc(guideId).get();
        if (!userDoc.exists) continue;

        const userData = userDoc.data();
        guides.push({
            guideId,
            guideName: userData.fullName || 'Unknown',
            priority: userData.priority || 0,
        });
    }

    guides.sort((a, b) => b.priority - a.priority);
    return guides;
}

/**
 * Get active buses sorted by priority descending
 */
async function getAvailableBuses() {
    const snapshot = await db.collection('buses')
        .where('isActive', '==', true)
        .get();

    const buses = snapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data(),
    }));

    buses.sort((a, b) => (b.priority || 0) - (a.priority || 0));
    return buses;
}

/**
 * Auto-accept applied shifts for the top-ranked guides.
 * Returns the list of all accepted guides (already accepted + newly accepted).
 */
async function autoAcceptTopGuides(dateStr, guidesNeeded) {
    const alreadyAccepted = await getAcceptedGuides(dateStr);
    const stillNeeded = guidesNeeded - alreadyAccepted.length;

    if (stillNeeded <= 0) {
        console.log(`✅ Already have ${alreadyAccepted.length} accepted guides (need ${guidesNeeded})`);
        return alreadyAccepted.slice(0, guidesNeeded);
    }

    const appliedGuides = await getAppliedGuides(dateStr);
    if (appliedGuides.length === 0) {
        console.log('⚠️ No applied guides to accept');
        return alreadyAccepted;
    }

    // Accept top-ranked applied guides
    const toAccept = appliedGuides.slice(0, stillNeeded);
    const newlyAccepted = [];

    for (const guide of toAccept) {
        try {
            await db.collection('shifts').doc(guide.shiftId).update({
                status: 'accepted',
                updatedAt: new Date().toISOString(),
                adminNote: `Auto-accepted by system (ranked #${toAccept.indexOf(guide) + 1})`,
            });
            console.log(`✅ Auto-accepted shift for ${guide.guideName} (priority: ${guide.priority})`);
            newlyAccepted.push(guide);
        } catch (e) {
            console.error(`❌ Failed to accept shift for ${guide.guideName}:`, e.message);
        }
    }

    return [...alreadyAccepted, ...newlyAccepted].slice(0, guidesNeeded);
}

/**
 * Distribute bookings to guides using round-robin by pickup location groups.
 * Writes to pickup_assignments and cached_bookings.
 */
async function distributeBookings(dateStr, bookings, guides) {
    if (guides.length === 0 || bookings.length === 0) return false;

    // Sort bookings alphabetically by pickup location to group similar ones
    const sorted = [...bookings].sort((a, b) => {
        const locA = (a.pickupPlaceName || a.pickupLocation || '').toLowerCase();
        const locB = (b.pickupPlaceName || b.pickupLocation || '').toLowerCase();
        return locA.localeCompare(locB);
    });

    // Distribute round-robin
    const guideBookings = {};
    for (const guide of guides) {
        guideBookings[guide.guideId] = {
            guideId: guide.guideId,
            guideName: guide.guideName,
            bookings: [],
            totalPassengers: 0,
        };
    }

    sorted.forEach((booking, index) => {
        const guide = guides[index % guides.length];
        const passengers = booking.totalParticipants || booking.numberOfGuests || 0;
        guideBookings[guide.guideId].bookings.push(booking);
        guideBookings[guide.guideId].totalPassengers += passengers;
    });

    // Save to pickup_assignments
    const batch = db.batch();
    for (const [guideId, data] of Object.entries(guideBookings)) {
        const docRef = db.collection('pickup_assignments').doc(`${dateStr}_${guideId}`);
        batch.set(docRef, {
            guideId: data.guideId,
            guideName: data.guideName,
            date: dateStr,
            totalPassengers: data.totalPassengers,
            bookings: data.bookings.map(b => ({
                id: b.id || b.bookingId,
                customerFullName: b.customerFullName || b.customerName || '',
                pickupPlaceName: b.pickupPlaceName || b.pickupLocation || '',
                pickupTime: b.pickupTime || '',
                numberOfGuests: b.totalParticipants || b.numberOfGuests || 0,
                phoneNumber: b.customerPhone || b.phoneNumber || '',
                email: b.customerEmail || b.email || '',
                confirmationCode: b.confirmationCode || '',
            })),
            updatedAt: new Date().toISOString(),
            autoDispatched: true,
        }, { merge: true });
    }

    // Also update cached_bookings with guide assignments
    const updatedBookings = bookings.map(booking => {
        const bookingId = booking.id || booking.bookingId;
        for (const [guideId, data] of Object.entries(guideBookings)) {
            if (data.bookings.some(b => (b.id || b.bookingId) === bookingId)) {
                return { ...booking, assignedGuideId: guideId, assignedGuideName: data.guideName };
            }
        }
        return booking;
    });

    const cacheRef = db.collection('cached_bookings').doc(dateStr);
    batch.set(cacheRef, { bookings: updatedBookings, updatedAt: new Date().toISOString() }, { merge: true });

    await batch.commit();

    // Also write individual assignment docs per booking
    const individualBatch = db.batch();
    for (const [guideId, data] of Object.entries(guideBookings)) {
        for (const booking of data.bookings) {
            const bookingId = booking.id || booking.bookingId;
            if (bookingId) {
                const ref = db.collection('pickup_assignments').doc(`${dateStr}_booking_${bookingId}`);
                individualBatch.set(ref, {
                    bookingId,
                    guideId: data.guideId,
                    guideName: data.guideName,
                    date: dateStr,
                    updatedAt: new Date().toISOString(),
                    autoDispatched: true,
                }, { merge: true });
            }
        }
    }
    await individualBatch.commit();

    console.log(`✅ Distributed ${bookings.length} bookings to ${guides.length} guides`);
    return true;
}

/**
 * Assign buses to guides (one per guide, by priority order)
 */
async function assignBuses(dateStr, guides) {
    const buses = await getAvailableBuses();
    const batch = db.batch();

    for (let i = 0; i < guides.length && i < buses.length; i++) {
        const guide = guides[i];
        const bus = buses[i];
        const docRef = db.collection('bus_guide_assignments').doc(`${dateStr}_${guide.guideId}`);

        batch.set(docRef, {
            guideId: guide.guideId,
            guideName: guide.guideName,
            busId: bus.id,
            busName: bus.name || 'Unknown Bus',
            date: dateStr,
            updatedAt: new Date().toISOString(),
            autoDispatched: true,
        }, { merge: true });

        console.log(`🚌 Assigned bus ${bus.name} to ${guide.guideName}`);
    }

    await batch.commit();
}

/**
 * Check if bookings are already distributed for a date
 */
async function isAlreadyDistributed(dateStr) {
    const snapshot = await db.collection('pickup_assignments')
        .where('date', '==', dateStr)
        .limit(1)
        .get();

    if (snapshot.empty) return false;

    // Check if any assignment has bookings
    for (const doc of snapshot.docs) {
        const data = doc.data();
        if (data.bookings && data.bookings.length > 0) return true;
    }
    return false;
}

/**
 * Record that auto-dispatch ran for a date (prevents re-running)
 */
async function markDispatched(dateStr, action) {
    await db.collection('auto_dispatch_log').doc(`${dateStr}_${action}`).set({
        date: dateStr,
        action,
        executedAt: new Date().toISOString(),
    });
}

/**
 * Check if auto-dispatch action already ran for a date
 */
async function hasAlreadyRun(dateStr, action) {
    const doc = await db.collection('auto_dispatch_log').doc(`${dateStr}_${action}`).get();
    return doc.exists;
}

// ============================================
// MAIN AUTO-DISPATCH LOGIC
// ============================================

async function runAutoDispatch() {
    const dateStr = getTodayDateStr();
    const icelandNow = getIcelandMinutesSinceMidnight();
    const icelandHour = getIcelandHour();

    console.log(`🤖 Auto-dispatch check: ${dateStr}, Iceland time: ${Math.floor(icelandNow / 60)}:${String(icelandNow % 60).padStart(2, '0')}`);

    // Get today's bookings
    const bookings = await getTodayBookings(dateStr);
    if (bookings.length === 0) {
        console.log('📭 No bookings for today, nothing to do');
        return { action: 'none', reason: 'no_bookings' };
    }

    const totalPax = getTotalPassengers(bookings);
    const guidesNeeded = calculateGuidesNeeded(totalPax);
    console.log(`📊 ${bookings.length} bookings, ${totalPax} passengers, need ${guidesNeeded} guides`);

    // === NOON AUTO-ACCEPT ===
    if (icelandHour >= 12 && !(await hasAlreadyRun(dateStr, 'noon_accept'))) {
        const appliedGuides = await getAppliedGuides(dateStr);
        const alreadyAccepted = await getAcceptedGuides(dateStr);
        const totalAvailable = appliedGuides.length + alreadyAccepted.length;

        if (totalAvailable < guidesNeeded) {
            // Not enough guides — send understaffing warning
            const shortage = guidesNeeded - totalAvailable;
            console.log(`⚠️ Understaffed! Need ${guidesNeeded} guides, only ${totalAvailable} available (${shortage} short)`);
            await sendNotificationToAdminsOnly(
                '⚠️ Understaffed Tonight!',
                `Need ${guidesNeeded} guides for ${totalPax} passengers but only ${totalAvailable} applied/accepted. ${shortage} more guide${shortage > 1 ? 's' : ''} needed!`,
                { type: 'understaffed', date: dateStr, needed: guidesNeeded, available: totalAvailable, shortage }
            );
        }

        if (appliedGuides.length > 0 || alreadyAccepted.length < guidesNeeded) {
            console.log(`🕛 Noon auto-accept: ${appliedGuides.length} applied, ${alreadyAccepted.length} already accepted, need ${guidesNeeded}`);
            const accepted = await autoAcceptTopGuides(dateStr, guidesNeeded);
            await markDispatched(dateStr, 'noon_accept');

            const acceptedNames = accepted.map(g => g.guideName).join(', ');
            await sendNotificationToAdminsOnly(
                '🕛 Auto-Accept Complete',
                `Accepted ${accepted.length}/${guidesNeeded} guides for tonight: ${acceptedNames}`,
                { type: 'auto_accept', date: dateStr, guides: acceptedNames }
            );

            return { action: 'noon_accept', accepted: accepted.length, needed: guidesNeeded };
        } else {
            // All needed guides already accepted, just mark as done
            await markDispatched(dateStr, 'noon_accept');
        }
    }

    // === 30-MIN AUTO-DISPATCH ===
    const earliestPickup = getEarliestPickupMinutes(bookings);
    if (earliestPickup === null) {
        console.log('⚠️ No valid pickup times found');
        return { action: 'none', reason: 'no_pickup_times' };
    }

    const minutesUntilPickup = earliestPickup - icelandNow;
    console.log(`⏰ ${minutesUntilPickup} minutes until earliest pickup`);

    if (minutesUntilPickup <= 30 && minutesUntilPickup > 0) {
        const distributed = await isAlreadyDistributed(dateStr);

        if (!distributed && !(await hasAlreadyRun(dateStr, 'dispatch_30min'))) {
            console.log(`🤖 30-min auto-dispatch triggered!`);

            // Accept guides if not already done
            const selectedGuides = await autoAcceptTopGuides(dateStr, guidesNeeded);
            if (selectedGuides.length === 0) {
                console.log('⚠️ No guides available');
                return { action: 'failed', reason: 'no_guides' };
            }

            // Distribute
            await distributeBookings(dateStr, bookings, selectedGuides);

            // Assign buses
            await assignBuses(dateStr, selectedGuides);

            await markDispatched(dateStr, 'dispatch_30min');

            const guideNames = selectedGuides.map(g => g.guideName).join(', ');
            await sendNotificationToAdminsOnly(
                '🤖 Auto-Dispatch Complete',
                `Distributed ${bookings.length} bookings to ${selectedGuides.length} guides: ${guideNames}`,
                { type: 'auto_dispatch', date: dateStr, guides: guideNames, bookings: bookings.length }
            );

            return { action: 'dispatched', guides: selectedGuides.length, bookings: bookings.length };
        }
    }

    // === 10-MIN LAST-MINUTE RE-DISPATCH ===
    if (minutesUntilPickup <= 10 && minutesUntilPickup > 0) {
        const distributed = await isAlreadyDistributed(dateStr);
        if (distributed) {
            // Check for unassigned bookings
            const unassigned = bookings.filter(b => !b.assignedGuideId);
            if (unassigned.length > 0 && !(await hasAlreadyRun(dateStr, `lastminute_${Math.floor(icelandNow / 5)}`))) {
                console.log(`🤖 Last-minute: ${unassigned.length} unassigned bookings`);

                const acceptedGuides = await getAcceptedGuides(dateStr);
                if (acceptedGuides.length > 0) {
                    await distributeBookings(dateStr, bookings, acceptedGuides);
                    await markDispatched(dateStr, `lastminute_${Math.floor(icelandNow / 5)}`);

                    await sendNotificationToAdminsOnly(
                        '🤖 Last-Minute Redistribution',
                        `${unassigned.length} new bookings redistributed to ${acceptedGuides.length} guides`,
                        { type: 'last_minute_dispatch', date: dateStr, newBookings: unassigned.length }
                    );

                    return { action: 'last_minute', newBookings: unassigned.length };
                }
            }
        }
    }

    return { action: 'none', reason: 'no_action_needed', minutesUntilPickup };
}

// ============================================
// EXPORTED FUNCTIONS
// ============================================

/**
 * Scheduled: Run auto-dispatch check every 5 minutes
 */
const autoDispatchScheduled = onSchedule(
    {
        schedule: 'every 5 minutes',
        timeZone: 'Atlantic/Reykjavik',
        region: 'us-central1',
    },
    async () => {
        console.log('🤖 Scheduled auto-dispatch check...');
        try {
            const result = await runAutoDispatch();
            console.log('🤖 Auto-dispatch result:', JSON.stringify(result));
            return result;
        } catch (error) {
            console.error('❌ Auto-dispatch failed:', error);
            return null;
        }
    }
);

/**
 * Manual trigger for auto-dispatch (for testing or forcing)
 */
const autoDispatchManual = onCall(
    { region: 'us-central1' },
    async (request) => {
        if (!request.auth) {
            throw new Error('Authentication required');
        }
        console.log('🤖 Manual auto-dispatch triggered by:', request.auth.uid);
        return await runAutoDispatch();
    }
);

module.exports = {
    autoDispatchScheduled,
    autoDispatchManual,
    // Exported for testing
    calculateGuidesNeeded,
    runAutoDispatch,
};
