// ============================================
// AURORA ADVISOR V2 - Complete Overhaul
// Two-stage AI: Truth extraction → Recommendation
// Normal guide language, no mystical talk
// ============================================

const { onCall } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const Anthropic = require('@anthropic-ai/sdk');

const db = admin.firestore();

// ============================================
// HELPER FUNCTIONS
// ============================================

// Calculate destination point from lat/lng + bearing + distance
function calculateDestination(lat, lng, bearingDeg, distanceKm) {
    const R = 6371;
    const lat1 = lat * Math.PI / 180;
    const lng1 = lng * Math.PI / 180;
    const bearing = bearingDeg * Math.PI / 180;
    const d = distanceKm / R;

    const lat2 = Math.asin(
        Math.sin(lat1) * Math.cos(d) + Math.cos(lat1) * Math.sin(d) * Math.cos(bearing)
    );
    const lng2 = lng1 + Math.atan2(
        Math.sin(bearing) * Math.sin(d) * Math.cos(lat1),
        Math.cos(d) - Math.sin(lat1) * Math.sin(lat2)
    );

    return {
        lat: lat2 * 180 / Math.PI,
        lng: lng2 * 180 / Math.PI,
    };
}

// Reverse geocode to get place name
async function reverseGeocode(lat, lng) {
    try {
        const apiKey = process.env.GOOGLE_MAPS_API_KEY;
        if (!apiKey) {
            return `${lat.toFixed(2)}°N, ${Math.abs(lng).toFixed(2)}°W`;
        }

        const url = `https://maps.googleapis.com/maps/api/geocode/json?latlng=${lat},${lng}&result_type=locality|administrative_area_level_2&key=${apiKey}`;
        const response = await fetch(url);
        const data = await response.json();

        if (data.results && data.results.length > 0) {
            for (const result of data.results) {
                for (const comp of result.address_components || []) {
                    if (comp.types.includes('locality')) {
                        return comp.long_name;
                    }
                }
            }
            return data.results[0].formatted_address.split(',')[0].trim();
        }
        return `${lat.toFixed(2)}°N, ${Math.abs(lng).toFixed(2)}°W`;
    } catch (e) {
        console.error('Geocoding error:', e);
        return `${lat.toFixed(2)}°N, ${Math.abs(lng).toFixed(2)}°W`;
    }
}

// Check if user is in a city (has light pollution)
async function checkIfInCity(lat, lng) {
    try {
        const apiKey = process.env.GOOGLE_MAPS_API_KEY;
        if (!apiKey) {
            return { isInCity: false, placeName: 'Unknown' };
        }

        const url = `https://maps.googleapis.com/maps/api/geocode/json?latlng=${lat},${lng}&key=${apiKey}`;
        const response = await fetch(url);
        const data = await response.json();

        if (data.results && data.results.length > 0) {
            const types = data.results[0].types || [];
            const cityTypes = ['locality', 'sublocality', 'neighborhood', 'administrative_area_level_3'];
            const isInCity = types.some(t => cityTypes.includes(t));

            let placeName = 'Unknown';
            for (const result of data.results) {
                for (const comp of result.address_components || []) {
                    if (comp.types.includes('locality')) {
                        placeName = comp.long_name;
                        break;
                    }
                }
                if (placeName !== 'Unknown') break;
            }

            // Also check if it's a known Icelandic city
            const knownCities = ['Reykjavík', 'Reykjavik', 'Akureyri', 'Keflavík', 'Keflavik', 'Hafnarfjörður', 'Kópavogur'];
            if (knownCities.some(c => placeName.includes(c))) {
                return { isInCity: true, placeName };
            }

            return { isInCity, placeName };
        }
        return { isInCity: false, placeName: 'Unknown' };
    } catch (e) {
        console.error('City check error:', e);
        return { isInCity: false, placeName: 'Unknown' };
    }
}

// Get darkness hours based on month (simplified for Iceland)
function getDarknessHours(date = new Date()) {
    const month = date.getMonth();
    const hour = date.getHours();

    // Iceland darkness schedule (astronomical twilight)
    const schedules = {
        0: { start: '16:00', end: '10:00', darkHours: [16, 17, 18, 19, 20, 21, 22, 23, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9] },
        1: { start: '18:00', end: '08:00', darkHours: [18, 19, 20, 21, 22, 23, 0, 1, 2, 3, 4, 5, 6, 7] },
        2: { start: '20:00', end: '06:00', darkHours: [20, 21, 22, 23, 0, 1, 2, 3, 4, 5] },
        3: { start: '22:00', end: '04:00', darkHours: [22, 23, 0, 1, 2, 3] },
        4: { start: '23:30', end: '02:30', darkHours: [23, 0, 1, 2] },
        5: { start: 'N/A', end: 'N/A', darkHours: [] },
        6: { start: 'N/A', end: 'N/A', darkHours: [] },
        7: { start: '23:00', end: '03:00', darkHours: [23, 0, 1, 2] },
        8: { start: '21:00', end: '05:00', darkHours: [21, 22, 23, 0, 1, 2, 3, 4] },
        9: { start: '19:00', end: '07:00', darkHours: [19, 20, 21, 22, 23, 0, 1, 2, 3, 4, 5, 6] },
        10: { start: '17:00', end: '09:00', darkHours: [17, 18, 19, 20, 21, 22, 23, 0, 1, 2, 3, 4, 5, 6, 7, 8] },
        11: { start: '15:30', end: '10:30', darkHours: [15, 16, 17, 18, 19, 20, 21, 22, 23, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10] },
    };

    const schedule = schedules[month];
    const isDark = schedule.darkHours.includes(hour);

    return {
        isDark,
        darknessStartsAt: schedule.start,
        darknessEndsAt: schedule.end,
        hoursOfDarkness: schedule.darkHours.length,
    };
}

// Get moon phase and illumination
function getMoonData(date = new Date()) {
    const year = date.getFullYear();
    const month = date.getMonth() + 1;
    const day = date.getDate();

    // Lunar phase calculation
    const c = Math.floor(365.25 * year);
    const e = Math.floor(30.6 * month);
    const jd = c + e + day - 694039.09;
    const phase = jd / 29.53058867;
    const phasePercent = phase - Math.floor(phase);

    // Illumination (0 at new moon, 100 at full moon)
    const illumination = Math.round((1 - Math.cos(phasePercent * 2 * Math.PI)) / 2 * 100);

    // Phase name
    let phaseName;
    if (illumination < 5) phaseName = 'New Moon';
    else if (illumination < 45) phaseName = phasePercent < 0.5 ? 'Waxing Crescent' : 'Waning Crescent';
    else if (illumination < 55) phaseName = phasePercent < 0.5 ? 'First Quarter' : 'Last Quarter';
    else if (illumination < 95) phaseName = phasePercent < 0.5 ? 'Waxing Gibbous' : 'Waning Gibbous';
    else phaseName = 'Full Moon';

    return {
        phase: phaseName,
        illumination,
        isSignificant: illumination > 85,
    };
}

// Get direction names for 8 cardinal directions
async function getDirectionNames(lat, lng, distanceKm = 35) {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    const bearings = [0, 45, 90, 135, 180, 225, 270, 315];
    const result = {};

    const promises = directions.map(async (dir, i) => {
        const dest = calculateDestination(lat, lng, bearings[i], distanceKm);
        const name = await reverseGeocode(dest.lat, dest.lng);
        return { dir, name, dest };
    });

    const results = await Promise.all(promises);
    for (const { dir, name, dest } of results) {
        result[dir] = { name, lat: dest.lat, lng: dest.lng };
    }

    return result;
}

// ============================================
// STAGE 1: EXTRACT TRUTH FROM IMAGE
// ============================================
async function extractCloudTruth(anthropic, imageBase64) {
    const truthPrompt = `You are analyzing a satellite cloud map.

ONLY report what you literally see. No recommendations, no poetry.

For each compass direction visible from center, report:
- CLEAR: Can see brown/green terrain clearly
- PARTLY_CLOUDY: Some haze but terrain partially visible  
- CLOUDY: White/gray haze blocking terrain
- OCEAN: Dark blue water (not relevant for driving)

Respond with ONLY this JSON (no other text):
{
  "observations": {
    "N": "CLEAR" | "PARTLY_CLOUDY" | "CLOUDY" | "OCEAN",
    "NE": "...",
    "E": "...",
    "SE": "...",
    "S": "...",
    "SW": "...",
    "W": "...",
    "NW": "..."
  },
  "clearest_directions": ["list 2-3 clearest"],
  "cloudiest_directions": ["list 2-3 cloudiest"],
  "overall_assessment": "mostly_clear" | "mixed" | "mostly_cloudy"
}`;

    const response = await anthropic.messages.create({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 500,
        system: truthPrompt,
        messages: [{
            role: 'user',
            content: [
                { type: 'image', source: { type: 'base64', media_type: 'image/png', data: imageBase64 } },
                { type: 'text', text: 'Report what you see in each direction. Just facts.' }
            ]
        }]
    });

    const text = response.content.filter(b => b.type === 'text').map(b => b.text).join('');
    console.log('Stage 1 raw:', text.substring(0, 300));

    const match = text.match(/\{[\s\S]*\}/);
    if (match) {
        try {
            return JSON.parse(match[0]);
        } catch (e) {
            console.error('Stage 1 JSON parse error:', e);
        }
    }

    // Fallback
    return {
        observations: { N: 'CLEAR', NE: 'CLEAR', E: 'CLEAR', SE: 'PARTLY_CLOUDY', S: 'CLOUDY', SW: 'CLOUDY', W: 'CLOUDY', NW: 'PARTLY_CLOUDY' },
        clearest_directions: ['N', 'NE', 'E'],
        cloudiest_directions: ['S', 'SW', 'W'],
        overall_assessment: 'mixed'
    };
}

// ============================================
// STAGE 2: GENERATE RECOMMENDATION
// ============================================
async function generateRecommendation(anthropic, truthData, factors) {
    const { userLocation, spaceWeather, darkness, moon, directionNames } = factors;

    const prompt = `You are a practical aurora tour guide giving advice.

TONE: Speak like a normal, friendly tour guide. No mystical language, no poetry. Just clear, helpful advice.

BAD: "Fellow seekers of the northern lights, tonight holds promise..."
GOOD: "Conditions look decent tonight. Head south toward Ölfus for clearer skies."

## CURRENT CONDITIONS:

**Cloud Cover (from satellite):**
${JSON.stringify(truthData.observations, null, 2)}
Clearest: ${truthData.clearest_directions.join(', ')}
Cloudiest: ${truthData.cloudiest_directions.join(', ')}
Overall: ${truthData.overall_assessment}

**Space Weather:**
- Bz: ${spaceWeather.bz} nT (${spaceWeather.bz < -5 ? 'GOOD' : spaceWeather.bz < 0 ? 'OK' : 'WEAK'})
- BzH (30min avg): ${spaceWeather.bzH} (${spaceWeather.bzH > 3 ? 'HIGH - aurora likely!' : spaceWeather.bzH > 1 ? 'MODERATE' : 'LOW'})
- Speed: ${spaceWeather.speed} km/s
- Kp: ${spaceWeather.kp}

**User Location:**
- At: ${userLocation.placeName}
- In city: ${userLocation.isInCity ? 'YES (light pollution)' : 'NO (dark location)'}

**Darkness:**
- Dark enough: ${darkness.isDark ? 'YES' : 'NO - wait until ' + darkness.darknessStartsAt}

**Moon:**
- ${moon.illumination}% ${moon.phase}
- Factor: ${moon.isSignificant ? 'YES - may wash out faint aurora' : 'NO'}

**Nearby Places:**
${Object.entries(directionNames).map(([dir, info]) => `- ${dir}: ${info.name}`).join('\n')}

## DECISION RULES:

1. If user is OUTSIDE city AND clear sky to north → Recommend STAY
2. If user is IN city → Recommend DRIVE (light pollution)
3. If cloudy everywhere → DRIVE to least cloudy, warn conditions are poor

## RESPONSE (JSON only):

{
  "action": "STAY" | "DRIVE",
  "direction": "N" | "NE" | "E" etc (only if DRIVE),
  "destination_name": "Place name" (only if DRIVE),
  "distance_km": 35,
  "travel_time_min": 30,
  
  "summary": "1-2 sentence recommendation in normal guide language",
  
  "aurora_probability": 0.0-1.0,
  "clear_sky_probability": 0.0-1.0,
  "viewing_probability": 0.0-1.0,
  
  "bz_status": "STRONG" | "MODERATE" | "WEAK" | "QUIET",
  "bz_trend": "IMPROVING" | "STABLE" | "DECLINING",
  
  "factors_summary": {
    "darkness": "Dark enough" or "Wait until X",
    "moon": "Not a factor" or "85% - may wash out faint aurora",
    "clouds": "Clear to N and NE" or description,
    "space_weather": "Bz favorable" or description
  }
}`;

    const response = await anthropic.messages.create({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 800,
        system: prompt,
        messages: [{
            role: 'user',
            content: 'Based on all factors, give your recommendation. Normal guide language, prefer staying if in a good spot.'
        }]
    });

    const text = response.content.filter(b => b.type === 'text').map(b => b.text).join('');
    console.log('Stage 2 raw:', text.substring(0, 400));

    const match = text.match(/\{[\s\S]*\}/);
    if (match) {
        try {
            return JSON.parse(match[0]);
        } catch (e) {
            console.error('Stage 2 JSON parse error:', e);
        }
    }

    // Fallback
    return {
        action: 'STAY',
        summary: 'Unable to analyze conditions. Check the sky yourself.',
        aurora_probability: 0.5,
        clear_sky_probability: 0.5,
        viewing_probability: 0.5,
        bz_status: 'MODERATE',
        bz_trend: 'STABLE',
        factors_summary: {
            darkness: darkness.isDark ? 'Dark enough' : `Wait until ${darkness.darknessStartsAt}`,
            moon: moon.isSignificant ? `${moon.illumination}% - may wash out faint aurora` : 'Not a factor',
            clouds: 'Check satellite image',
            space_weather: 'Check BzH chart'
        }
    };
}

// ============================================
// MAIN FUNCTION
// ============================================
exports.getAuroraAdvisorRecommendation = onCall(
    {
        secrets: ['ANTHROPIC_API_KEY', 'GOOGLE_MAPS_API_KEY'],
        region: 'europe-west1',
        timeoutSeconds: 120,
        memory: '512MiB',
    },
    async (request) => {
        try {
            const { location, satelliteImages, spaceWeather } = request.data;

            console.log('🚀 Aurora Advisor V2 starting...');

            if (!satelliteImages || satelliteImages.length === 0) {
                throw new Error('No satellite image provided');
            }

            const lat = location?.lat || location?.latitude || 64.1;
            const lng = location?.lng || location?.longitude || -21.9;

            const anthropic = new Anthropic({
                apiKey: process.env.ANTHROPIC_API_KEY,
            });

            // STAGE 1: Extract truth from image
            console.log('📷 Stage 1: Extracting cloud truth...');
            const truthData = await extractCloudTruth(anthropic, satelliteImages[0]);
            console.log('✅ Truth:', JSON.stringify(truthData).substring(0, 200));

            // Gather factors
            console.log('📊 Gathering factors...');
            const [cityCheck, directionNames] = await Promise.all([
                checkIfInCity(lat, lng),
                getDirectionNames(lat, lng, 35),
            ]);

            const darkness = getDarknessHours();
            const moon = getMoonData();

            const factors = {
                userLocation: {
                    lat,
                    lng,
                    isInCity: cityCheck.isInCity,
                    placeName: cityCheck.placeName,
                },
                spaceWeather: {
                    bz: spaceWeather?.bz || 0,
                    bzH: spaceWeather?.bzH || 0,
                    speed: spaceWeather?.speed || 400,
                    density: spaceWeather?.density || 5,
                    kp: spaceWeather?.kp || 2,
                },
                darkness,
                moon,
                directionNames,
            };

            // STAGE 2: Generate recommendation
            console.log('💡 Stage 2: Generating recommendation...');
            const recommendation = await generateRecommendation(anthropic, truthData, factors);
            console.log('✅ Recommendation:', recommendation.action, '-', recommendation.summary?.substring(0, 100));

            // Get destination coords if driving
            let destinationCoords = null;
            let navigationUrl = null;
            if (recommendation.action === 'DRIVE' && recommendation.direction) {
                const destInfo = directionNames[recommendation.direction];
                if (destInfo) {
                    destinationCoords = { lat: destInfo.lat, lng: destInfo.lng };
                    navigationUrl = `https://www.google.com/maps/dir/?api=1&destination=${destInfo.lat},${destInfo.lng}&travelmode=driving`;
                }
            }

            // Log to Firestore
            await db.collection('ai_recommendations_v2').add({
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                location: { lat, lng },
                truthData,
                factors: { ...factors, directionNames: Object.keys(directionNames) }, // Simplified
                recommendation,
            });

            // Build final response
            const result = {
                // Core
                action: recommendation.action,
                direction: recommendation.direction || null,
                destination: recommendation.action === 'DRIVE' ? {
                    name: recommendation.destination_name || directionNames[recommendation.direction]?.name,
                    lat: destinationCoords?.lat,
                    lng: destinationCoords?.lng,
                } : null,
                navigation_url: navigationUrl,
                distance_km: recommendation.distance_km || 35,
                travel_time_min: recommendation.travel_time_min || 30,

                // Summary (normal guide language)
                summary: recommendation.summary,

                // Probabilities
                aurora_probability: recommendation.aurora_probability || 0.5,
                clear_sky_probability: recommendation.clear_sky_probability || 0.5,
                viewing_probability: recommendation.viewing_probability || 0.5,

                // Space weather
                bz_status: recommendation.bz_status || 'MODERATE',
                bz_trend: recommendation.bz_trend || 'STABLE',
                bzH_value: spaceWeather?.bzH || 0,
                kp_index: spaceWeather?.kp || 2,

                // Factors
                factors: recommendation.factors_summary || {},

                // Truth data
                cloud_truth: truthData,

                // Darkness & Moon
                darkness: {
                    isDark: darkness.isDark,
                    startsAt: darkness.darknessStartsAt,
                    endsAt: darkness.darknessEndsAt,
                },
                moon: {
                    phase: moon.phase,
                    illumination: moon.illumination,
                    isSignificant: moon.isSignificant,
                },

                // Disclaimer
                disclaimer: 'Satellite images can lag behind actual conditions. If skies look different outside, trust your eyes.',

                // Meta
                generatedAt: new Date().toISOString(),
                version: 'v2',
            };

            console.log('🎉 Done!', result.action);
            return result;

        } catch (error) {
            console.error('❌ Error:', error);
            return {
                error: true,
                message: error.message,
                action: 'STAY',
                summary: 'Unable to analyze. Check conditions yourself.',
                disclaimer: 'Satellite images can lag behind actual conditions.',
            };
        }
    }
);

// Quick assessment (no image needed)
exports.getQuickAuroraAssessment = onCall(
    { region: 'europe-west1' },
    async (request) => {
        const { spaceWeather } = request.data;
        let score = 0;

        if (spaceWeather.bz < -10) score += 40;
        else if (spaceWeather.bz < -5) score += 25;
        else if (spaceWeather.bz < 0) score += 10;

        if (spaceWeather.speed > 500) score += 20;
        else if (spaceWeather.speed > 400) score += 15;

        if (spaceWeather.kp >= 5) score += 25;
        else if (spaceWeather.kp >= 4) score += 20;

        const probability = Math.min(score / 100, 1.0);
        return { aurora_probability: probability };
    }
);
