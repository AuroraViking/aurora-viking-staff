// ============================================
// AURORA ADVISOR - AI Recommendation Engine
// ============================================

const { onCall } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const Anthropic = require('@anthropic-ai/sdk');

const db = admin.firestore();

// Main recommendation function WITH LEARNING CONTEXT
exports.getAuroraAdvisorRecommendation = onCall(
    {
        secrets: ['ANTHROPIC_API_KEY'],
        region: 'europe-west1',
        timeoutSeconds: 60,
        memory: '512MiB',
    },
    async (request) => {
        try {
            const { location, spaceWeather, cloudCover, satelliteImages, currentTime, darknessWindow } = request.data;

            if (!location || !spaceWeather) {
                throw new Error('Missing required fields: location and spaceWeather');
            }

            // Fetch accumulated AI learnings
            const learningsContext = await fetchLearningsContext();

            const anthropic = new Anthropic({
                apiKey: process.env.ANTHROPIC_API_KEY,
            });

            const systemPrompt = buildSystemPromptWithLearnings(learningsContext);
            const userPrompt = buildUserPrompt(location, spaceWeather, cloudCover, currentTime, darknessWindow);

            const messageContent = [];

            // Add satellite images if provided
            if (satelliteImages && satelliteImages.length > 0) {
                messageContent.push({
                    type: 'text',
                    text: `SATELLITE CLOUD COVER MAP (CRITICAL - ANALYZE THIS IMAGE CAREFULLY):
This is a real-time satellite image showing cloud cover. 
- WHITE/BRIGHT areas = CLOUDS (bad for viewing)
- DARK/CLEAR areas = NO CLOUDS (good for viewing)
- The blue dot shows the user's CURRENT LOCATION
- You MUST recommend driving toward DARK/CLEAR areas, NOT cloudy areas
- If user's current location is already clear, you may recommend staying near
- Look at the image and identify which direction has clearest skies:`,
                });
                for (let i = 0; i < satelliteImages.length; i++) {
                    messageContent.push({
                        type: 'image',
                        source: {
                            type: 'base64',
                            media_type: 'image/png',
                            data: satelliteImages[i],
                        },
                    });
                }
            }

            messageContent.push({ type: 'text', text: userPrompt });

            const response = await anthropic.messages.create({
                model: 'claude-sonnet-4-20250514',
                max_tokens: 2000,
                system: systemPrompt,
                messages: [{ role: 'user', content: messageContent }],
            });

            const responseText = response.content
                .filter(block => block.type === 'text')
                .map(block => block.text)
                .join('');

            const jsonMatch = responseText.match(/\{[\s\S]*\}/);
            if (!jsonMatch) {
                throw new Error('Failed to parse AI response');
            }

            const recommendation = JSON.parse(jsonMatch[0]);
            recommendation.generatedAt = new Date().toISOString();
            recommendation.modelUsed = 'claude-sonnet-4-20250514';
            recommendation.learningsUsed = learningsContext.count;

            console.log('✅ Recommendation generated with', learningsContext.count, 'learnings');
            return recommendation;

        } catch (error) {
            console.error('❌ Aurora Advisor error:', error);
            return {
                error: true,
                message: error.message,
                recommendation: 'Unable to generate recommendation. Please check conditions manually.',
                aurora_probability: null,
                clear_sky_probability: null,
                confidence: 0,
            };
        }
    }
);

// Quick assessment without full AI (just calculations)
exports.getQuickAuroraAssessment = onCall(
    {
        region: 'europe-west1',
    },
    async (request) => {
        try {
            const { spaceWeather } = request.data;
            let auroraScore = 0;

            if (spaceWeather.bz < -10) auroraScore += 40;
            else if (spaceWeather.bz < -5) auroraScore += 25;
            else if (spaceWeather.bz < 0) auroraScore += 10;

            if (spaceWeather.speed > 500) auroraScore += 20;
            else if (spaceWeather.speed > 400) auroraScore += 15;
            else if (spaceWeather.speed > 300) auroraScore += 5;

            if (spaceWeather.kp >= 5) auroraScore += 25;
            else if (spaceWeather.kp >= 4) auroraScore += 20;
            else if (spaceWeather.kp >= 3) auroraScore += 10;

            if (spaceWeather.density > 10) auroraScore += 15;
            else if (spaceWeather.density > 5) auroraScore += 10;

            const probability = Math.min(auroraScore / 100, 1.0);

            let assessment;
            if (probability > 0.7) assessment = 'Excellent aurora conditions!';
            else if (probability > 0.5) assessment = 'Good aurora potential';
            else if (probability > 0.3) assessment = 'Moderate conditions';
            else assessment = 'Quiet conditions';

            return { aurora_probability: probability, assessment };
        } catch (error) {
            return { error: true, message: error.message };
        }
    }
);

// Fetch learnings from Firestore
async function fetchLearningsContext() {
    try {
        const snapshot = await db.collection('ai_learnings')
            .where('isActive', '==', true)
            .orderBy('confidence', 'desc')
            .limit(30)
            .get();

        if (snapshot.empty) return { text: '', count: 0 };

        const learnings = snapshot.docs.map(doc => doc.data());
        const byCategory = {};
        for (const learning of learnings) {
            const cat = learning.category || 'general';
            if (!byCategory[cat]) byCategory[cat] = [];
            byCategory[cat].push(learning);
        }

        let text = '\n\n=== ACCUMULATED LEARNINGS FROM HISTORICAL DATA ===\n';
        text += '(Patterns learned from actual aurora sighting reports)\n\n';

        for (const [category, items] of Object.entries(byCategory)) {
            text += `### ${category.toUpperCase().replace('_', ' ')}\n`;
            for (const item of items) {
                text += `• ${item.insight} [${Math.round(item.confidence * 100)}% conf, ${item.supportingSightings} sightings]\n`;
            }
            text += '\n';
        }
        text += '=== END LEARNINGS ===\n';

        return { text, count: learnings.length };
    } catch (error) {
        console.error('Error fetching learnings:', error);
        return { text: '', count: 0 };
    }
}

function buildSystemPromptWithLearnings(learningsContext) {
    const basePrompt = `You are Heimdallr, the Aurora Advisor AI - an expert aurora hunting assistant.

AURORA SCIENCE (Universal):
- Bz (IMF North-South): NEGATIVE = good. <-5nT good, <-10nT excellent, <-20nT storm
- Bt: Total field strength
- Solar Wind Speed: >400 km/s = enhanced
- Density: >5/cm³ = more particles
- Kp Index visibility by latitude:
  * Kp 9: visible to 48°N (Seattle, Paris, Munich)
  * Kp 7: visible to 52°N (London, Berlin, Calgary)
  * Kp 5: visible to 58°N (Scotland, Norway, Alaska)
  * Kp 3: visible to 64°N+ (Iceland, Northern Scandinavia)
- BzH: Accumulated negative Bz - sustained activity

LOCATION AWARENESS:
- Use the provided coordinates to determine local context
- Recommend driving AWAY from the nearest urban center for dark skies
- Estimate travel times: ~45min per 50km on good roads
- Max recommended travel: ~100km unless exceptional aurora conditions
- The user's starting point is their provided location, NOT a fixed city

MOON IMPACT ON AURORA VIEWING:
- Moon illumination >85% significantly reduces aurora visibility - need stronger aurora (Kp 4+)
- Moon below horizon = ideal (no moon interference)
- Moon above horizon + bright = challenging, recommend looking away from moon
- During full moon periods, stronger aurora activity is needed for good viewing
- Always mention moon conditions in your recommendation

VIEWING DIRECTION GUIDANCE:
- LOW activity (Kp <3): Look towards NORTHERN horizon, aurora appears low on horizon
- MEDIUM activity (Kp 3-5): Aurora may appear overhead, look north to overhead
- HIGH activity (Kp 5+): Aurora can appear OVERHEAD and even toward SOUTH
- In Southern Hemisphere: reverse these directions (look SOUTH for aurora)
- Always include viewing direction advice in recommendations

LIGHT POLLUTION - MOST CRITICAL FACTOR:
- ALWAYS recommend leaving urban areas for dark skies - this is NON-NEGOTIABLE
- Aurora can be photographed with a camera even with +Bz and Kp 0 in a dark, clear, moonless sky!
- With camera/long exposure, faint aurora is visible that eyes cannot see
- NEVER recommend staying in light-polluted areas like city centers
- Minimum 20-30km from urban centers for decent dark skies
- Point camera toward NORTHERN horizon in quiet conditions
- Dark skies + clear weather = can always attempt aurora photography

ICELAND SPECIFIC (use when coordinates are in Iceland ~63-66°N, 13-24°W):
- Þingvellir: 47 km NE Reykjavik - Open valley, dark skies
- Grótta: 5 km W Reykjavik - Quick access but light pollution nearby
- Seljalandsfoss: 120 km SE Reykjavik - South coast, darker skies
- Akranes: 50 km N Reykjavik - Often clearer, good darkness
- Hvalfjörður: 35 km N Reykjavik - Excellent dark skies
- Vik: 180 km SE Reykjavik - Far south, very dark`;

    return learningsContext.text ? basePrompt + learningsContext.text : basePrompt;
}

function buildUserPrompt(location, spaceWeather, cloudCover, currentTime, darknessWindow) {
    // Determine darkness status
    let darknessInfo = '';
    if (darknessWindow && darknessWindow.nauticalStart) {
        const now = new Date(currentTime || Date.now());
        const [startHour, startMin] = (darknessWindow.nauticalStart || '').split(':').map(Number);
        const [endHour, endMin] = (darknessWindow.nauticalEnd || '').split(':').map(Number);

        if (!isNaN(startHour)) {
            const darknessStart = new Date(now);
            darknessStart.setHours(startHour, startMin || 0, 0, 0);

            // If darkness starts after current time, we're in daylight
            if (now < darknessStart) {
                darknessInfo = `\n🌅 DAYLIGHT STATUS: Currently NOT dark enough for aurora viewing.\n   Nautical darkness begins at: ${darknessWindow.nauticalStart}\n   Include this in your recommendation!`;
            } else {
                darknessInfo = `\n🌙 DARKNESS: Currently dark enough for viewing (darkness window: ${darknessWindow.nauticalStart} - ${darknessWindow.nauticalEnd})`;
            }
        }
    }

    return `
CURRENT CONDITIONS:

📍 Location: ${location.lat.toFixed(4)}°N, ${Math.abs(location.lng).toFixed(4)}°W
⏰ Time: ${currentTime || new Date().toISOString()}
${darknessInfo}

🌡️ SPACE WEATHER:
- Bz: ${spaceWeather.bz?.toFixed(2) || 'N/A'} nT
- Bt: ${spaceWeather.bt?.toFixed(2) || 'N/A'} nT
- Speed: ${spaceWeather.speed?.toFixed(0) || 'N/A'} km/s
- Density: ${spaceWeather.density?.toFixed(2) || 'N/A'} /cm³
- Kp: ${spaceWeather.kp?.toFixed(1) || 'N/A'}
- BzH: ${spaceWeather.bzH?.toFixed(2) || 'N/A'} nT·hr
- AE Index: ${spaceWeather.aeIndex || 'N/A'} nT

☁️ Cloud cover: ${cloudCover != null ? cloudCover + '%' : 'Unknown'}

Provide recommendation using real-time data AND accumulated learnings.
IMPORTANT: If it's currently daylight, still provide the space weather analysis BUT clearly note it's not dark enough yet and when darkness begins.
IMPORTANT: Always include viewing direction advice and moon impact assessment.

OUTPUT AS JSON:
{
  "recommendation": "Drive X km [direction] toward [destination]",
  "destination": { "name": "string", "lat": number, "lng": number },
  "distance_km": number,
  "direction": "N/NE/E/SE/S/SW/W/NW/STAY",
  "travel_time_minutes": number,
  "aurora_probability": 0.0-1.0,
  "clear_sky_probability": 0.0-1.0,
  "combined_viewing_probability": 0.0-1.0,
  "cloud_movement": { "direction": "string", "speed_kmh": number, "analysis": "string" },
  "space_weather_analysis": "string",
  "viewing_direction": "Look toward [N/NE/E/overhead/etc] - based on activity level",
  "moon_note": "Moon impact assessment (e.g. '95% moon above horizon - need strong aurora' or 'New moon - ideal conditions')",
  "confidence": 0.0-1.0,
  "reasoning": "string",
  "applied_learnings": ["learnings used"],
  "alternative_options": [{ "destination": "string", "probability": number, "distance_km": number }],
  "urgency": "low/medium/high",
  "darkness_note": "string (e.g. 'Not dark until 17:30' or 'Currently in darkness window')",
  "special_notes": "string"
}`;
}

