# 🚀 Phase 2 Quick Start Guide
> Ready to implement AI Draft Responses when you wake up!

## ⏱️ Estimated Time: 4-6 hours

---

## Step 1: Add Anthropic API Key (5 minutes)

```powershell
cd C:\Users\kolbe\aurora_viking_staff\functions
firebase functions:secrets:set ANTHROPIC_API_KEY
# Paste your Claude API key when prompted
```

Get your API key from: https://console.anthropic.com/

---

## Step 2: Add NPM Dependency (2 minutes)

```powershell
cd C:\Users\kolbe\aurora_viking_staff\functions
npm install @anthropic-ai/sdk
```

---

## Step 3: Add AI Draft Generation to Cloud Functions

Open `functions/index.js` and add after the gmail section:

```javascript
// ============================================
// PHASE 2: AI DRAFT RESPONSES
// ============================================

const Anthropic = require('@anthropic-ai/sdk');

/**
 * Generate AI draft response when new inbound message is created
 */
exports.generateAiDraft = onDocumentCreated(
  {
    document: 'messages/{messageId}',
    region: 'us-central1',
    secrets: ['ANTHROPIC_API_KEY'],
  },
  async (event) => {
    const messageData = event.data.data();
    const messageId = event.params.messageId;
    
    // Only generate drafts for inbound messages
    if (messageData.direction !== 'inbound') {
      console.log('⏭️ Skipping AI draft - not inbound message');
      return;
    }
    
    console.log('🧠 Generating AI draft for message:', messageId);
    
    try {
      // Get conversation history
      const conversationId = messageData.conversationId;
      const messagesSnapshot = await db.collection('messages')
        .where('conversationId', '==', conversationId)
        .orderBy('timestamp', 'asc')
        .limit(10) // Last 10 messages for context
        .get();
      
      const conversationHistory = messagesSnapshot.docs.map(doc => ({
        direction: doc.data().direction,
        content: doc.data().content,
        subject: doc.data().subject,
      }));
      
      // Get customer info
      const customerDoc = await db.collection('customers').doc(messageData.customerId).get();
      const customer = customerDoc.data() || {};
      
      // Look up booking if detected
      const bookingContext = await getBookingContext(messageData.detectedBookingNumbers);
      
      // Generate draft with Claude
      const draft = await generateDraftWithClaude({
        message: messageData,
        customer,
        bookingContext,
        conversationHistory,
      });
      
      // Save draft to message
      await db.collection('messages').doc(messageId).update({
        aiDraft: {
          content: draft.content,
          confidence: draft.confidence,
          suggestedTone: draft.tone,
          generatedAt: admin.firestore.FieldValue.serverTimestamp(),
          reasoning: draft.reasoning,
        },
        status: 'draftReady',
      });
      
      console.log('✅ AI draft saved for message:', messageId);
    } catch (error) {
      console.error('❌ Error generating AI draft:', error);
      // Don't fail the whole thing - just log and continue
    }
  }
);

// Helper: Get booking context from Bokun (cached)
async function getBookingContext(bookingNumbers) {
  if (!bookingNumbers || bookingNumbers.length === 0) {
    return 'No booking numbers detected in the message.';
  }
  
  // For now, just return the detected booking numbers
  // TODO: Later, query Bokun API for full booking details
  return `Customer mentioned booking(s): ${bookingNumbers.join(', ')}`;
}

// Helper: Generate draft with Claude
async function generateDraftWithClaude({ message, customer, bookingContext, conversationHistory }) {
  const anthropic = new Anthropic({
    apiKey: process.env.ANTHROPIC_API_KEY,
  });
  
  const systemPrompt = `You are a helpful customer service agent for Aurora Viking, 
a Northern Lights and aurora borealis tour company based in Reykjavik, Iceland.

COMPANY INFO:
- We run Northern Lights tours every night (weather permitting)
- Tours depart from Reykjavik, pickup from hotels/bus stops
- Standard tour is 4-5 hours
- Tours can be rescheduled for free if aurora not seen
- Bookings reference format: AV-XXXXX

CUSTOMER CONTEXT:
- Name: ${customer.name || 'Unknown'}
- Email: ${customer.email || message.channelMetadata?.gmail?.from || 'Unknown'}
- Past interactions: ${customer.pastInteractions || 0}
- VIP: ${customer.vipStatus ? 'Yes' : 'No'}

BOOKING CONTEXT:
${bookingContext}

TONE GUIDELINES:
- Be warm, friendly, and professional
- Use the customer's name if known
- Be helpful and solution-oriented
- For weather questions, be optimistic but honest
- For reschedule requests, be accommodating

Generate a helpful, professional response to the customer's inquiry.`;

  // Build message history
  const messages = conversationHistory.map(msg => ({
    role: msg.direction === 'inbound' ? 'user' : 'assistant',
    content: msg.subject ? `Subject: ${msg.subject}\n\n${msg.content}` : msg.content,
  }));
  
  // Ensure the last message is the current one
  if (messages.length === 0 || messages[messages.length - 1].content !== message.content) {
    const currentContent = message.subject 
      ? `Subject: ${message.subject}\n\n${message.content}`
      : message.content;
    messages.push({
      role: 'user',
      content: currentContent,
    });
  }

  const response = await anthropic.messages.create({
    model: 'claude-sonnet-4-20250514',
    max_tokens: 1024,
    system: systemPrompt,
    messages: messages,
  });
  
  const draftContent = response.content[0].text;
  
  // Classify confidence based on message type
  let confidence = 0.85;
  const contentLower = message.content.toLowerCase();
  
  if (contentLower.includes('cancel') || contentLower.includes('refund')) {
    confidence = 0.6; // Lower confidence for sensitive topics
  } else if (contentLower.includes('weather') || contentLower.includes('aurora')) {
    confidence = 0.9; // High confidence for common questions
  } else if (contentLower.includes('pickup') || contentLower.includes('hotel')) {
    confidence = 0.88;
  }
  
  return {
    content: draftContent,
    confidence,
    tone: 'friendly',
    reasoning: 'Generated based on conversation context and company guidelines',
  };
}
```

---

## Step 4: Update Flutter UI to Show AI Drafts

### 4.1 Update `lib/modules/inbox/conversation_screen.dart`

Add this widget above the message input:

```dart
// Add to imports if needed
import '../../core/models/messaging/message.dart';

// In the build method, before the message input TextField:
_buildAiDraftPanel(context),

// Add this method to the class:
Widget _buildAiDraftPanel(BuildContext context) {
  // Get the latest message with an AI draft
  final messages = _controller.messages;
  final messageWithDraft = messages.lastWhere(
    (m) => m.aiDraft != null && m.direction == MessageDirection.inbound,
    orElse: () => Message.empty(),
  );
  
  final draft = messageWithDraft.aiDraft;
  if (draft == null || draft.content.isEmpty) {
    return const SizedBox.shrink();
  }
  
  return Container(
    margin: const EdgeInsets.all(12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.blue.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.blue.withOpacity(0.3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.blue, size: 18),
            const SizedBox(width: 8),
            const Text('AI Draft', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _getConfidenceColor(draft.confidence),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${(draft.confidence * 100).toInt()}%',
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          draft.content,
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('Use Draft'),
                onPressed: () {
                  _messageController.text = draft.content;
                },
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () {
                // TODO: Dismiss draft
              },
              child: const Text('Dismiss'),
            ),
          ],
        ),
      ],
    ),
  );
}

Color _getConfidenceColor(double confidence) {
  if (confidence >= 0.85) return Colors.green;
  if (confidence >= 0.7) return Colors.orange;
  return Colors.red;
}
```

---

## Step 5: Deploy and Test

```powershell
cd C:\Users\kolbe\aurora_viking_staff\functions
npm run deploy
```

Then:
1. Send an email to info@auroraviking.com
2. Wait for polling (2 minutes)
3. Open conversation in app
4. See AI draft appear!

---

## 🎯 Expected Result

When a customer email comes in:
1. Email is processed by `pollGmailInbox` (existing)
2. Message is created in Firestore (existing)
3. **NEW**: `generateAiDraft` trigger fires
4. Claude analyzes the email + context
5. Draft is saved to the message document
6. Flutter UI shows the draft with "Use Draft" button
7. Staff can edit and send the response

---

## 📝 Quick Wins After Phase 2

1. **Intent Detection** - Add to generateAiDraft to classify what the customer wants
2. **Booking Lookup** - Query Bokun API to include actual booking details in the prompt
3. **Draft Approval Stats** - Track how often staff use vs. edit AI drafts

---

## 🆘 Troubleshooting

### "ANTHROPIC_API_KEY not found"
```powershell
firebase functions:secrets:access ANTHROPIC_API_KEY
```

### "Module not found: @anthropic-ai/sdk"
```powershell
cd functions
npm install @anthropic-ai/sdk
npm run deploy
```

### Draft not appearing
1. Check Firebase console for function logs
2. Verify message has `direction: 'inbound'`
3. Check that `aiDraft` field exists on message document

---

Happy coding! 🌌

