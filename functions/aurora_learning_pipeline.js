// ============================================
// HEIMDALLR LEARNING PIPELINE
// ============================================

const { onCall } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');
const Anthropic = require('@anthropic-ai/sdk');

const db = admin.firestore();

// Weekly scheduled learning
exports.runLearningPipeline = onSchedule(
    {
        schedule: 'every sunday 06:00',
        timeZone: 'Atlantic/Reykjavik',
        secrets: ['ANTHROPIC_API_KEY'],
        region: 'europe-west1',
        timeoutSeconds: 300,
        memory: '1GiB',
    },
    async (event) => {
        console.log('🧠 Starting Heimdallr Learning Pipeline...');
        await executeLearningPipeline();
    }
);

// Manual trigger
exports.triggerLearningPipeline = onCall(
    {
        secrets: ['ANTHROPIC_API_KEY'],
        region: 'europe-west1',
        timeoutSeconds: 300,
        memory: '1GiB',
    },
    async (request) => {
        console.log('🧠 Manually triggered Learning Pipeline...');
        return await executeLearningPipeline();
    }
);

async function executeLearningPipeline() {
    const sessionId = db.collection('learning_sessions').doc().id;

    try {
        await db.collection('learning_sessions').doc(sessionId).set({
            startedAt: admin.firestore.FieldValue.serverTimestamp(),
            status: 'running',
            sightingsAnalyzed: 0,
        });

        const sightingsSnapshot = await db.collection('aurora_sightings')
            .where('usedForTraining', '==', false)
            .orderBy('timestamp', 'desc')
            .limit(200)
            .get();

        if (sightingsSnapshot.empty) {
            await db.collection('learning_sessions').doc(sessionId).update({
                completedAt: admin.firestore.FieldValue.serverTimestamp(),
                status: 'completed',
                sightingsAnalyzed: 0,
            });
            return { success: true, message: 'No new sightings to process' };
        }

        const sightings = sightingsSnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
        console.log(`📊 Analyzing ${sightings.length} sightings...`);

        const existingLearnings = await db.collection('ai_learnings').where('isActive', '==', true).get();
        const existingInsights = existingLearnings.docs.map(doc => doc.data().insight);

        const aiResult = await analyzeWithClaude(sightings, existingInsights);

        let newLearningsCreated = 0;
        let learningsUpdated = 0;

        for (const learning of aiResult.learnings) {
            const existing = await findSimilarLearning(learning.category, learning.insight);

            if (existing) {
                await db.collection('ai_learnings').doc(existing.id).update({
                    confidence: learning.confidence,
                    supportingSightings: admin.firestore.FieldValue.increment(learning.supportingSightings),
                    sightingIds: admin.firestore.FieldValue.arrayUnion(...learning.sightingIds),
                    version: admin.firestore.FieldValue.increment(1),
                });
                learningsUpdated++;
            } else {
                await db.collection('ai_learnings').add({
                    ...learning,
                    learnedAt: admin.firestore.FieldValue.serverTimestamp(),
                    isActive: true,
                    learningSessionId: sessionId,
                    version: 1,
                });
                newLearningsCreated++;
            }
        }

        const batch = db.batch();
        for (const sighting of sightings) {
            batch.update(db.collection('aurora_sightings').doc(sighting.id), { usedForTraining: true });
        }
        await batch.commit();

        await db.collection('learning_sessions').doc(sessionId).update({
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
            status: 'completed',
            sightingsAnalyzed: sightings.length,
            newLearningsCreated,
            learningsUpdated,
            tokensUsed: aiResult.tokensUsed || 0,
        });

        console.log(`✅ Learning complete! Created ${newLearningsCreated}, updated ${learningsUpdated}`);
        return { success: true, sightingsAnalyzed: sightings.length, newLearningsCreated, learningsUpdated };

    } catch (error) {
        console.error('❌ Learning pipeline error:', error);
        await db.collection('learning_sessions').doc(sessionId).update({
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
            status: 'failed',
            errorMessage: error.message,
        });
        return { success: false, error: error.message };
    }
}

async function analyzeWithClaude(sightings, existingInsights) {
    const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

    const systemPrompt = `You are Heimdallr's Learning Module. Analyze aurora sighting data to identify patterns.

EXISTING LEARNINGS (don't repeat):
${existingInsights.length > 0 ? existingInsights.map(i => `- ${i}`).join('\n') : 'None yet'}

Find patterns for: when aurora visible, where strongest, what conditions lead to best viewing, location-specific patterns, timing patterns.`;

    const userPrompt = `Analyze ${sightings.length} sightings:\n\n${formatSightings(sightings)}\n\nOUTPUT JSON:
{
  "learnings": [{
    "category": "space_weather|location|timing|cloud_pattern|seasonal|guide_wisdom|correlation",
    "insight": "Clear insight",
    "confidence": 0.0-1.0,
    "supportingSightings": number,
    "sightingIds": ["ids"]
  }],
  "summary": "Brief summary"
}`;

    const response = await anthropic.messages.create({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 4000,
        system: systemPrompt,
        messages: [{ role: 'user', content: userPrompt }],
    });

    const text = response.content.filter(b => b.type === 'text').map(b => b.text).join('');
    const parsed = JSON.parse(text.match(/\{[\s\S]*\}/)[0]);
    return { learnings: parsed.learnings || [], tokensUsed: Math.round(text.length / 4) };
}

function formatSightings(sightings) {
    return sightings.map((s, i) => `
[${s.id}] ${s.timestamp?.toDate?.() || s.timestamp}
Location: ${s.locationName || 'Unknown'} (${s.distanceFromReykjavik || '?'}km ${s.directionFromReykjavik || ''})
Aurora: ${s.auroraIntensity}/5, ${s.auroraColor || ''} ${s.auroraMovement || ''}
Weather: Bz=${s.bzAtSighting || '?'}, Speed=${s.speedAtSighting || '?'}, Kp=${s.kpAtSighting || '?'}
Clouds: ${s.cloudCoverPercent || '?'}%
Notes: ${s.guideNotes || 'None'}`).join('\n---\n');
}

async function findSimilarLearning(category, insight) {
    const existing = await db.collection('ai_learnings')
        .where('category', '==', category)
        .where('isActive', '==', true)
        .get();

    for (const doc of existing.docs) {
        const existingWords = new Set(doc.data().insight.toLowerCase().split(/\s+/).filter(w => w.length > 4));
        const newWords = insight.toLowerCase().split(/\s+/).filter(w => w.length > 4);
        const overlap = newWords.filter(w => existingWords.has(w)).length;
        if (overlap > newWords.length * 0.6) return { id: doc.id, ...doc.data() };
    }
    return null;
}

// Auto-create sighting from shift report
exports.createSightingFromShiftReport = onDocumentCreated(
    { document: 'shift_reports/{reportId}', region: 'europe-west1' },
    async (event) => {
        const report = event.data.data();
        if (!report.auroraStrength || report.auroraStrength < 1) return;

        try {
            await db.collection('aurora_sightings').add({
                timestamp: report.timestamp || admin.firestore.FieldValue.serverTimestamp(),
                guideId: report.guideId || '',
                guideName: report.guideName || '',
                shiftReportId: event.params.reportId,
                latitude: report.bestViewingLocation?.latitude || 64.1466,
                longitude: report.bestViewingLocation?.longitude || -21.9426,
                locationName: report.bestViewingLocationName || '',
                distanceFromReykjavik: report.distanceFromReykjavik || null,
                directionFromReykjavik: report.directionFromReykjavik || null,
                auroraIntensity: report.auroraStrength,
                auroraColor: report.auroraColor || null,
                auroraMovement: report.auroraMovement || null,
                photographable: report.auroraStrength >= 3,
                visibleDurationMinutes: report.auroraDurationMinutes || null,
                bzAtSighting: report.spaceWeather?.bz || null,
                speedAtSighting: report.spaceWeather?.speed || null,
                kpAtSighting: report.spaceWeather?.kp || null,
                cloudCoverPercent: report.cloudCover || null,
                guideNotes: report.notes || null,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                usedForTraining: false,
            });
            console.log(`✅ Created sighting from shift report ${event.params.reportId}`);
        } catch (error) {
            console.error('❌ Error creating sighting:', error);
        }
    }
);

// Get learnings for display
exports.getLearningsContext = onCall({ region: 'europe-west1' }, async () => {
    const snapshot = await db.collection('ai_learnings')
        .where('isActive', '==', true)
        .orderBy('confidence', 'desc')
        .limit(50)
        .get();
    return { learnings: snapshot.docs.map(d => ({ id: d.id, ...d.data() })), count: snapshot.size };
});
