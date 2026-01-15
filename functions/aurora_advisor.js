// ============================================
// AURORA ADVISOR - Two-Phase Vision Analysis
// Phase 1: Get literal truth from images
// Phase 2: Generate engaging description
// ============================================

const { onCall } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const Anthropic = require('@anthropic-ai/sdk');

const db = admin.firestore();

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
            return null; // Will use coordinates as fallback
        }

        const url = `https://maps.googleapis.com/maps/api/geocode/json?latlng=${lat},${lng}&result_type=locality|administrative_area_level_2|administrative_area_level_1&key=${apiKey}`;

        const response = await fetch(url);
        const data = await response.json();

        if (data.results && data.results.length > 0) {
            for (const result of data.results) {
                for (const component of result.address_components) {
                    if (component.types.includes('locality')) {
                        return component.long_name;
                    }
                }
            }
            return data.results[0].formatted_address.split(',')[0].trim();
        }
        return null;
    } catch (e) {
        console.error('Geocoding error:', e);
        return null;
    }
}

// Get direction info for a specific direction
async function getDestinationInfo(lat, lng, direction, distanceKm = 35) {
    const directionAngles = {
        'N': 0, 'NNE': 22.5, 'NE': 45, 'ENE': 67.5,
        'E': 90, 'ESE': 112.5, 'SE': 135, 'SSE': 157.5,
        'S': 180, 'SSW': 202.5, 'SW': 225, 'WSW': 247.5,
        'W': 270, 'WNW': 292.5, 'NW': 315, 'NNW': 337.5
    };

    const bearing = directionAngles[direction] || 90;
    const dest = calculateDestination(lat, lng, bearing, distanceKm);
    const placeName = await reverseGeocode(dest.lat, dest.lng);

    return {
        lat: dest.lat,
        lng: dest.lng,
        name: placeName, // will be null if geocoding fails
    };
}

// Two-phase recommendation
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

            console.log('📥 Request received:', {
                hasLocation: !!location,
                hasImages: !!satelliteImages,
                imageCount: satelliteImages?.length || 0,
            });

            if (!satelliteImages || satelliteImages.length === 0) {
                throw new Error('No images provided');
            }

            const lat = location?.lat || location?.latitude || 64.1;
            const lng = location?.lng || location?.longitude || -21.9;

            const anthropic = new Anthropic({
                apiKey: process.env.ANTHROPIC_API_KEY,
            });

            // ============================================
            // PHASE 1: Get literal truth from images
            // ============================================
            const phase1Prompt = `You are analyzing aurora conditions. Answer ONLY with facts you can see.

## IMAGE 1: Bz Chart (Space Weather)
- RED area = negative Bz = GOOD for aurora
- GREEN area = positive Bz = less favorable
- Look at: Is line above or below zero? Trending up or down?

## IMAGE 2: Cloud Map (Satellite)
- Compass rose with 16 directions from center
- WHITE/GRAY = clouds, BROWN/GREEN terrain = clear
- Which directions show clear terrain?

## RESPOND WITH ONLY THIS JSON (no other text):
{
  "bz_position": "above_zero" | "below_zero" | "at_zero",
  "bz_trend": "improving" | "worsening" | "stable",
  "aurora_favorable": true | false,
  "clear_directions": ["list directions with visible terrain"],
  "cloudy_directions": ["list directions with haze"],
  "best_direction": "single best direction (E, NE, SE, etc)",
  "confidence": 0.0-1.0
}`;

            const phase1Content = [
                { type: 'text', text: 'Analyze these images and respond with JSON only:' },
            ];

            for (const img of satelliteImages) {
                phase1Content.push({
                    type: 'image',
                    source: { type: 'base64', media_type: 'image/png', data: img },
                });
            }

            console.log('🔍 Phase 1: Getting literal truth...');
            const phase1Response = await anthropic.messages.create({
                model: 'claude-sonnet-4-20250514',
                max_tokens: 500,
                system: phase1Prompt,
                messages: [{ role: 'user', content: phase1Content }],
            });

            const phase1Text = phase1Response.content
                .filter(b => b.type === 'text')
                .map(b => b.text)
                .join('');

            console.log('Phase 1 response:', phase1Text.substring(0, 300));

            // Parse Phase 1 result
            let truth;
            const jsonMatch = phase1Text.match(/\{[\s\S]*\}/);
            if (jsonMatch) {
                try {
                    truth = JSON.parse(jsonMatch[0]);
                } catch (e) {
                    console.warn('JSON parse error:', e.message);
                }
            }

            // Fallback if parsing failed
            if (!truth) {
                truth = {
                    bz_position: 'at_zero',
                    bz_trend: 'stable',
                    aurora_favorable: false,
                    clear_directions: ['E'],
                    cloudy_directions: ['W'],
                    best_direction: 'E',
                    confidence: 0.5
                };
            }

            // Get destination info
            const bestDir = truth.best_direction || 'E';
            const destInfo = await getDestinationInfo(lat, lng, bestDir, 35);

            // Format destination name
            let destName;
            if (destInfo.name) {
                destName = destInfo.name;
            } else {
                // Format as readable coordinates
                destName = `${destInfo.lat.toFixed(2)}°N, ${Math.abs(destInfo.lng).toFixed(2)}°W`;
            }

            // Calculate probabilities
            let auroraProbability = 0.4;
            if (truth.bz_position === 'below_zero') auroraProbability += 0.3;
            if (truth.bz_trend === 'improving') auroraProbability += 0.15;
            if (truth.aurora_favorable) auroraProbability += 0.1;
            auroraProbability = Math.max(0.1, Math.min(0.95, auroraProbability));

            const clearCount = truth.clear_directions?.length || 1;
            const clearSkyProbability = Math.min(0.95, 0.3 + (clearCount * 0.1));
            const combinedProbability = (auroraProbability * 0.4) + (clearSkyProbability * 0.6);

            // ============================================
            // PHASE 2: Generate engaging description
            // ============================================
            console.log('✨ Phase 2: Generating engaging description...');

            const kpLevel = spaceWeather?.kp || 3;
            const phase2Prompt = `You are Heimdallr, the Norse god who watches for aurora. Write a brief, engaging aurora hunting guide (3-4 sentences max).

## CURRENT CONDITIONS (use these facts):
- Aurora probability: ${(auroraProbability * 100).toFixed(0)}%
- Clear sky probability: ${(clearSkyProbability * 100).toFixed(0)}%
- Best direction to drive: ${bestDir} toward ${destName}
- Bz status: ${truth.bz_position === 'below_zero' ? 'favorable (southward)' : truth.bz_position === 'above_zero' ? 'not ideal (northward)' : 'neutral'}
- Bz trend: ${truth.bz_trend}
- Clear skies toward: ${truth.clear_directions?.join(', ') || bestDir}
- Cloudy toward: ${truth.cloudy_directions?.join(', ') || 'W'}
- Kp index: ${kpLevel}

## AURORA VIEWING TIPS TO INCLUDE:
${kpLevel <= 3 ? '- With Kp at ' + kpLevel + ', aurora will appear low on the northern horizon - look north!' : ''}
${kpLevel >= 5 ? '- With Kp at ' + kpLevel + ', aurora may appear overhead or across the entire sky!' : ''}
${kpLevel > 3 && kpLevel < 5 ? '- With Kp at ' + kpLevel + ', look from north to overhead for best viewing' : ''}
- Remind them to get away from city lights to dark skies
- Mention the clear/cloudy directions naturally

## RULES:
- Do NOT mention "images", "charts", or "analysis"
- Write as if you're a knowledgeable local guide
- Be enthusiastic but professional
- Keep it to 3-4 sentences

Write the description now:`;

            const phase2Response = await anthropic.messages.create({
                model: 'claude-sonnet-4-20250514',
                max_tokens: 300,
                messages: [{ role: 'user', content: phase2Prompt }],
            });

            const description = phase2Response.content
                .filter(b => b.type === 'text')
                .map(b => b.text)
                .join('')
                .trim();

            console.log('Phase 2 description:', description.substring(0, 200));

            // Generate navigation URL
            const navigationUrl = `https://www.google.com/maps/dir/?api=1&destination=${destInfo.lat},${destInfo.lng}&travelmode=driving`;

            // Determine urgency
            const urgency = auroraProbability > 0.6 ? 'go_now' : auroraProbability > 0.4 ? 'good_time' : 'possible';

            // Log to Firestore
            await db.collection('ai_vision_analysis').add({
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                location: { lat, lng },
                phase1Truth: truth,
                probabilities: { auroraProbability, clearSkyProbability, combinedProbability },
            });

            // Build final response
            const finalResult = {
                // Core recommendation
                recommendation: `Drive ${bestDir} toward ${destName}`,
                direction: bestDir,
                destination: {
                    name: destName,
                    lat: destInfo.lat,
                    lng: destInfo.lng,
                },

                // Navigation
                navigation_url: navigationUrl,
                distance_km: 35,
                travel_time_minutes: 30,

                // Probabilities
                aurora_probability: auroraProbability,
                clear_sky_probability: clearSkyProbability,
                combined_viewing_probability: combinedProbability,
                confidence: truth.confidence || 0.7,

                // Engaging description (no image references!)
                description: description,
                urgency: urgency,

                // Raw truth for debugging/transparency
                analysis: {
                    bz_position: truth.bz_position,
                    bz_trend: truth.bz_trend,
                    aurora_favorable: truth.aurora_favorable,
                    clear_directions: truth.clear_directions,
                    cloudy_directions: truth.cloudy_directions,
                },

                // Space weather context
                kp_index: kpLevel,
                viewing_tip: kpLevel <= 3
                    ? 'Look low on the northern horizon'
                    : kpLevel >= 5
                        ? 'Aurora may appear overhead!'
                        : 'Look from north toward overhead',

                // Metadata
                generatedAt: new Date().toISOString(),
            };

            console.log('✅ Complete:', bestDir, '->', destName,
                `(Aurora: ${(auroraProbability * 100).toFixed(0)}%)`);

            return finalResult;

        } catch (error) {
            console.error('❌ Error:', error);
            return {
                error: true,
                message: error.message,
                recommendation: 'Unable to analyze. Check conditions manually.',
                confidence: 0,
            };
        }
    }
);

// Quick assessment without AI
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
        const assessment = probability > 0.7 ? 'Excellent!' :
            probability > 0.5 ? 'Good potential' :
                probability > 0.3 ? 'Moderate' : 'Quiet';

        return { aurora_probability: probability, assessment };
    }
);
