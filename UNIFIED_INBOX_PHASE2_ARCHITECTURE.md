# 🚀 Unified Inbox Phase 2: Website Chat, WhatsApp & AI Integration

## Overview

This document outlines the architecture for three major features:
1. **Website Chat Widget** - Custom HTML/JS embed to replace Wix chat
2. **WhatsApp Business Integration** - Connect WhatsApp Business API
3. **AI Draft Responses** - GPT-powered response suggestions

---

## 1. 🌐 Website Chat Widget

### Why Replace Wix Chat?
- Full control over data flow
- Direct integration with Unified Inbox
- Custom branding and UX
- No third-party dependencies
- Real-time sync with staff app

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        WEBSITE VISITOR                          │
│                    (auroraviking.is/com)                        │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                   CHAT WIDGET (Embedded)                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  aurora-chat.js + aurora-chat.css                        │   │
│  │  - Floating button (Aurora branding)                     │   │
│  │  - Chat window with message history                      │   │
│  │  - Typing indicators                                     │   │
│  │  - File/image upload                                     │   │
│  │  - Visitor identification (name, email, booking ref)     │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────┬───────────────────────────────────────────┘
                      │ WebSocket / Firestore
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                    FIREBASE BACKEND                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │  Firestore   │  │ Cloud Funcs  │  │  Realtime Database   │  │
│  │  - messages  │  │  - validate  │  │  - presence          │  │
│  │  - convos    │  │  - notify    │  │  - typing status     │  │
│  │  - customers │  │  - AI draft  │  │                      │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                    STAFF APP (Flutter)                          │
│                 Unified Inbox → Website Tab                     │
└─────────────────────────────────────────────────────────────────┘
```

### Implementation Files

```
web/
├── chat-widget/
│   ├── aurora-chat.js        # Main widget logic
│   ├── aurora-chat.css       # Styling (Aurora theme)
│   ├── aurora-chat.min.js    # Production bundle
│   └── embed-snippet.html    # Code to paste in Wix
│
functions/
├── src/
│   └── website-chat/
│       ├── createWebsiteSession.ts   # Anonymous session
│       ├── sendWebsiteMessage.ts     # Message handler
│       └── websitePresence.ts        # Online status
```

### Embed Code (for Wix)

```html
<!-- Aurora Viking Chat Widget -->
<script>
  window.AURORA_CHAT_CONFIG = {
    projectId: 'aurora-viking-staff',
    position: 'bottom-right',
    primaryColor: '#00BFA5',
    greeting: 'Hi! 👋 Ask us anything about Northern Lights tours!',
    offlineMessage: 'Leave a message and we\'ll get back to you!',
  };
</script>
<script src="https://aurora-viking-staff.web.app/chat-widget/aurora-chat.min.js" async></script>
```

### Key Features

| Feature | Description |
|---------|-------------|
| **Anonymous Sessions** | Visitors can chat without account, session persists via localStorage |
| **Smart Identification** | Prompt for name/email after first message, link to booking if provided |
| **Rich Messages** | Support images, links, booking cards |
| **Typing Indicators** | Real-time "Staff is typing..." |
| **Read Receipts** | Show when messages are seen |
| **Offline Mode** | Queue messages when offline, send on reconnect |
| **Mobile Responsive** | Full-screen on mobile, floating on desktop |

### Firestore Schema

```javascript
// Collection: website_sessions
{
  sessionId: "ws_abc123",
  
  // Visitor info (collected progressively)
  visitorName: "John",
  visitorEmail: "john@example.com",
  bookingRef: "BK-12345",
  
  // Tracking
  firstPageUrl: "https://auroraviking.is/tours",
  currentPageUrl: "https://auroraviking.is/checkout",
  userAgent: "...",
  ipCountry: "US",
  
  // Session state
  isOnline: true,
  lastSeen: Timestamp,
  createdAt: Timestamp,
  
  // Link to unified inbox
  conversationId: "conv_xyz789",
  customerId: "cust_..."
}
```

---

## 2. 📱 WhatsApp Business Integration

### Options

| Option | Pros | Cons | Cost |
|--------|------|------|------|
| **WhatsApp Business API (Meta)** | Official, reliable, templates | Complex setup, approval needed | ~$0.05-0.15/message |
| **Twilio WhatsApp** | Easy API, good docs | Middleman fees | ~$0.05/msg + Twilio fees |
| **360dialog** | EU-based, GDPR compliant | Less known | ~€50/mo + per message |

### Recommended: WhatsApp Business API via Twilio

Twilio provides a simpler integration path while still using the official WhatsApp Business API.

### Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                     CUSTOMER PHONE                              │
│                  WhatsApp: +354 XXX XXXX                        │
└─────────────────────┬──────────────────────────────────────────┘
                      │
                      ▼
┌────────────────────────────────────────────────────────────────┐
│                  WHATSAPP BUSINESS API                          │
│                     (via Twilio)                                │
└─────────────────────┬──────────────────────────────────────────┘
                      │ Webhook
                      ▼
┌────────────────────────────────────────────────────────────────┐
│              CLOUD FUNCTION: whatsappWebhook                    │
│  - Receive incoming messages                                    │
│  - Parse media attachments                                      │
│  - Create/update conversation in Firestore                      │
│  - Trigger AI draft generation                                  │
└─────────────────────┬──────────────────────────────────────────┘
                      │
                      ▼
┌────────────────────────────────────────────────────────────────┐
│                    FIRESTORE                                    │
│  messages (channel: 'whatsapp')                                 │
│  conversations (channel: 'whatsapp')                            │
└─────────────────────┬──────────────────────────────────────────┘
                      │
                      ▼
┌────────────────────────────────────────────────────────────────┐
│                    STAFF APP                                    │
│              Unified Inbox → WhatsApp Tab                       │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Reply → Cloud Function → Twilio → WhatsApp → Customer  │   │
│  └─────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────┘
```

### Setup Steps

1. **Create Twilio Account** → twilio.com
2. **Enable WhatsApp Sandbox** (for testing)
3. **Apply for WhatsApp Business Account** (production)
4. **Get WhatsApp-enabled Twilio number**
5. **Configure webhook URL** → `https://us-central1-aurora-viking-staff.cloudfunctions.net/whatsappWebhook`

### Cloud Function: whatsappWebhook

```javascript
// functions/src/whatsapp/webhook.ts
exports.whatsappWebhook = onRequest(async (req, res) => {
  const { From, Body, MediaUrl0, MessageSid } = req.body;
  
  // Parse phone number
  const phoneNumber = From.replace('whatsapp:', '');
  
  // Find or create customer
  const customer = await findOrCreateCustomerByPhone(phoneNumber);
  
  // Find or create conversation
  const conversation = await findOrCreateConversation({
    customerId: customer.id,
    channel: 'whatsapp',
    channelId: phoneNumber,
  });
  
  // Store message
  await db.collection('messages').add({
    conversationId: conversation.id,
    customerId: customer.id,
    channel: 'whatsapp',
    direction: 'inbound',
    content: Body,
    mediaUrl: MediaUrl0 || null,
    channelMetadata: {
      whatsapp: {
        messageSid: MessageSid,
        from: phoneNumber,
      }
    },
    timestamp: FieldValue.serverTimestamp(),
    status: 'delivered',
  });
  
  // Trigger AI draft
  await generateAiDraft(conversation.id, Body);
  
  res.status(200).send('OK');
});
```

### Sending Replies

```javascript
// functions/src/whatsapp/sendReply.ts
const twilio = require('twilio')(TWILIO_SID, TWILIO_AUTH_TOKEN);

exports.sendWhatsAppReply = onCall(async (request) => {
  const { conversationId, content } = request.data;
  
  // Get conversation to find phone number
  const convo = await db.collection('conversations').doc(conversationId).get();
  const phoneNumber = convo.data().channelMetadata.whatsapp.phoneNumber;
  
  // Send via Twilio
  const message = await twilio.messages.create({
    from: 'whatsapp:+354XXXXXXXX', // Your WhatsApp Business number
    to: `whatsapp:${phoneNumber}`,
    body: content,
  });
  
  // Store outbound message
  await db.collection('messages').add({
    conversationId,
    direction: 'outbound',
    content,
    channel: 'whatsapp',
    channelMetadata: {
      whatsapp: { messageSid: message.sid }
    },
    timestamp: FieldValue.serverTimestamp(),
    status: 'sent',
  });
  
  return { success: true, messageSid: message.sid };
});
```

### WhatsApp Message Templates

WhatsApp requires pre-approved templates for outbound messages (outside 24h window).

```javascript
// Suggested templates to register:
const templates = {
  booking_confirmation: {
    name: 'booking_confirmation',
    language: 'en',
    body: 'Hi {{1}}! Your Northern Lights tour is confirmed for {{2}}. Pickup: {{3}}. Questions? Reply here!',
  },
  photo_ready: {
    name: 'photo_ready',
    language: 'en', 
    body: 'Hi {{1}}! 📸 Your tour photos are ready! View them here: {{2}}',
  },
  review_request: {
    name: 'review_request',
    language: 'en',
    body: 'Hi {{1}}! Hope you enjoyed the Northern Lights! 🌌 Would you mind leaving us a quick review? {{2}}',
  },
};
```

---

## 3. 🤖 AI Draft Responses

### Overview

Use GPT-4 to generate draft responses for incoming messages. Staff can review, edit, and send with one tap.

### Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                   INCOMING MESSAGE                              │
│            (Gmail / Website / WhatsApp)                         │
└─────────────────────┬──────────────────────────────────────────┘
                      │ Firestore Trigger
                      ▼
┌────────────────────────────────────────────────────────────────┐
│           CLOUD FUNCTION: onNewInboundMessage                   │
│                                                                 │
│  1. Load conversation history (last 10 messages)                │
│  2. Load customer context (bookings, preferences)               │
│  3. Load relevant knowledge base docs                           │
│  4. Build prompt with context                                   │
│  5. Call OpenAI GPT-4                                           │
│  6. Store draft in Firestore                                    │
└─────────────────────┬──────────────────────────────────────────┘
                      │
                      ▼
┌────────────────────────────────────────────────────────────────┐
│                    FIRESTORE                                    │
│                                                                 │
│  conversations/{id}/aiDrafts/{draftId}                          │
│  {                                                              │
│    content: "Thank you for reaching out! ...",                  │
│    confidence: 0.92,                                            │
│    suggestedActions: ['send', 'edit', 'escalate'],              │
│    generatedAt: Timestamp,                                      │
│    status: 'pending' | 'sent' | 'edited' | 'rejected',          │
│    model: 'gpt-4-turbo',                                        │
│    tokensUsed: 450,                                             │
│  }                                                              │
└─────────────────────┬──────────────────────────────────────────┘
                      │
                      ▼
┌────────────────────────────────────────────────────────────────┐
│                    STAFF APP UI                                 │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  💡 AI Suggestion                               92% conf  │  │
│  │  ─────────────────────────────────────────────────────── │  │
│  │  "Thank you for reaching out! I'd be happy to help       │  │
│  │   you find photos from your January 5th tour with        │  │
│  │   guide Kristján. I'll have those ready for you          │  │
│  │   within 24 hours. Is there anything else I can          │  │
│  │   help with?"                                             │  │
│  │                                                           │  │
│  │  [✓ Send] [✏️ Edit] [🔄 Regenerate] [❌ Dismiss]          │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
```

### System Prompt

```javascript
const SYSTEM_PROMPT = `You are Aurora Viking's customer support AI assistant. 

ABOUT AURORA VIKING:
- Northern Lights tour operator in Reykjavik, Iceland
- Tours run from September to April
- Pickup from hotels in Reykjavik area
- Tours last 3-5 hours depending on conditions
- Free rebooking if no Northern Lights seen

YOUR ROLE:
- Draft helpful, friendly responses to customer inquiries
- Match the tone: professional but warm, excited about the aurora
- Keep responses concise (2-3 short paragraphs max)
- Use customer's name when known
- Reference their booking details when relevant

COMMON TOPICS:
1. Photo requests → Direct to photo folder, explain 24-48h processing time
2. Booking changes → Offer to help, mention free rebooking policy
3. Weather/conditions → Be honest but optimistic, mention our success rate
4. Pickup questions → Confirm pickup time (usually 30min before tour)
5. What to wear → Warm layers, we provide overalls and hot chocolate

GUIDELINES:
- Never make up booking details - say "let me check" if unsure
- For complaints, apologize sincerely and offer to make it right
- If question is complex, suggest they call or flag for human review
- End with an open question or offer of further help

OUTPUT FORMAT:
- Just the response text, no labels or prefixes
- Use line breaks for readability
- Include relevant emojis sparingly (🌌 ❄️ 📸)`;
```

### Cloud Function: generateAiDraft

```javascript
// functions/src/ai/generateDraft.ts
import OpenAI from 'openai';

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

exports.generateAiDraft = onDocumentCreated(
  'messages/{messageId}',
  async (event) => {
    const message = event.data.data();
    
    // Only for inbound messages
    if (message.direction !== 'inbound') return;
    
    // Get conversation context
    const conversationId = message.conversationId;
    const conversation = await db.collection('conversations').doc(conversationId).get();
    const customer = await db.collection('customers').doc(message.customerId).get();
    
    // Get recent message history
    const recentMessages = await db.collection('messages')
      .where('conversationId', '==', conversationId)
      .orderBy('timestamp', 'desc')
      .limit(10)
      .get();
    
    // Build context
    const context = buildContext(conversation.data(), customer.data(), recentMessages);
    
    // Generate draft
    const completion = await openai.chat.completions.create({
      model: 'gpt-4-turbo-preview',
      messages: [
        { role: 'system', content: SYSTEM_PROMPT },
        { role: 'system', content: `CONTEXT:\n${context}` },
        { role: 'user', content: message.content },
      ],
      temperature: 0.7,
      max_tokens: 500,
    });
    
    const draft = completion.choices[0].message.content;
    const confidence = calculateConfidence(completion);
    
    // Store draft
    await db.collection('conversations').doc(conversationId)
      .collection('aiDrafts').add({
        content: draft,
        confidence,
        messageId: event.params.messageId,
        generatedAt: FieldValue.serverTimestamp(),
        status: 'pending',
        model: 'gpt-4-turbo-preview',
        tokensUsed: completion.usage.total_tokens,
      });
    
    // Update conversation with draft indicator
    await db.collection('conversations').doc(conversationId).update({
      hasAiDraft: true,
      lastAiDraftAt: FieldValue.serverTimestamp(),
    });
  }
);

function buildContext(conversation, customer, messages) {
  let context = '';
  
  if (customer) {
    context += `CUSTOMER: ${customer.name || 'Unknown'}\n`;
    context += `Email: ${customer.email || 'Not provided'}\n`;
    if (customer.bookings?.length) {
      context += `Recent bookings: ${customer.bookings.slice(0, 3).join(', ')}\n`;
    }
  }
  
  if (conversation.subject) {
    context += `Subject: ${conversation.subject}\n`;
  }
  
  context += '\nCONVERSATION HISTORY:\n';
  messages.docs.reverse().forEach(doc => {
    const msg = doc.data();
    const role = msg.direction === 'inbound' ? 'Customer' : 'Staff';
    context += `${role}: ${msg.content.substring(0, 500)}\n\n`;
  });
  
  return context;
}
```

### Flutter UI: AI Draft Card

```dart
// lib/modules/inbox/widgets/ai_draft_card.dart

class AiDraftCard extends StatelessWidget {
  final AiDraft draft;
  final VoidCallback onSend;
  final VoidCallback onEdit;
  final VoidCallback onRegenerate;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AVColors.primaryTeal.withOpacity(0.1),
            AVColors.auroraGreen.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AVColors.primaryTeal.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.auto_awesome, color: AVColors.auroraGreen, size: 20),
              SizedBox(width: 8),
              Text('AI Suggestion', style: TextStyle(
                color: AVColors.textHigh,
                fontWeight: FontWeight.bold,
              )),
              Spacer(),
              _ConfidenceBadge(confidence: draft.confidence),
            ],
          ),
          
          SizedBox(height: 12),
          
          // Draft content
          Text(
            draft.content,
            style: TextStyle(
              color: AVColors.textHigh,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          
          SizedBox(height: 16),
          
          // Actions
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onSend,
                  icon: Icon(Icons.send, size: 18),
                  label: Text('Send'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AVColors.auroraGreen,
                    foregroundColor: AVColors.obsidian,
                  ),
                ),
              ),
              SizedBox(width: 8),
              IconButton(
                onPressed: onEdit,
                icon: Icon(Icons.edit, color: AVColors.primaryTeal),
                tooltip: 'Edit before sending',
              ),
              IconButton(
                onPressed: onRegenerate,
                icon: Icon(Icons.refresh, color: AVColors.textLow),
                tooltip: 'Regenerate',
              ),
              IconButton(
                onPressed: onDismiss,
                icon: Icon(Icons.close, color: AVColors.textLow),
                tooltip: 'Dismiss',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

### Photo Request AI Automation

Special handling for `photo@auroraviking.com`:

```javascript
// functions/src/ai/photoRequestHandler.ts

const PHOTO_SYSTEM_PROMPT = `You are handling photo requests for Aurora Viking tours.

TASK: Extract the following from the customer's email:
1. Tour date (if mentioned)
2. Guide name (if mentioned)
3. Customer name
4. Any specific requests

Then draft a response confirming you'll prepare their photos.

If aurora was strong that night (check shift reports), include a friendly review request.
If aurora was weak/not visible, just provide the photos without review request.

OUTPUT FORMAT:
{
  "extractedData": {
    "tourDate": "2026-01-05" or null,
    "guideName": "Kristján" or null,
    "customerName": "John" or null,
    "specialRequests": "..."
  },
  "draftResponse": "...",
  "shouldRequestReview": true/false,
  "confidence": 0.0-1.0
}`;

exports.handlePhotoRequest = onDocumentCreated(
  'messages/{messageId}',
  async (event) => {
    const message = event.data.data();
    
    // Only for photo inbox
    const conversation = await db.collection('conversations').doc(message.conversationId).get();
    if (conversation.data().inboxEmail !== 'photo@auroraviking.com') return;
    if (message.direction !== 'inbound') return;
    
    // Parse with AI
    const completion = await openai.chat.completions.create({
      model: 'gpt-4-turbo-preview',
      messages: [
        { role: 'system', content: PHOTO_SYSTEM_PROMPT },
        { role: 'user', content: message.content },
      ],
      response_format: { type: 'json_object' },
    });
    
    const parsed = JSON.parse(completion.choices[0].message.content);
    
    // Check shift report for aurora strength if we have a date
    let auroraStrength = null;
    if (parsed.extractedData.tourDate) {
      const shiftReport = await db.collection('shift_reports')
        .where('date', '==', parsed.extractedData.tourDate)
        .where('guide', '==', parsed.extractedData.guideName)
        .limit(1)
        .get();
      
      if (!shiftReport.empty) {
        auroraStrength = shiftReport.docs[0].data().auroraStrength;
        // Override AI's decision based on actual data
        parsed.shouldRequestReview = auroraStrength >= 3; // 1-5 scale
      }
    }
    
    // Store AI analysis and draft
    await db.collection('conversations').doc(message.conversationId)
      .collection('aiDrafts').add({
        content: parsed.draftResponse,
        confidence: parsed.confidence,
        extractedData: parsed.extractedData,
        shouldRequestReview: parsed.shouldRequestReview,
        auroraStrength,
        messageId: event.params.messageId,
        generatedAt: FieldValue.serverTimestamp(),
        status: 'pending',
        type: 'photo_request',
      });
  }
);
```

---

## 4. 📊 Knowledge Base for AI

To make AI responses accurate, we need a knowledge base:

### Firestore Collection: `knowledge_base`

```javascript
// Collection: knowledge_base
{
  id: "kb_tours_general",
  category: "tours",
  title: "General Tour Information",
  content: `
    Northern Lights tours run from September to April.
    Tours depart from Reykjavik, Iceland.
    Duration: 3-5 hours depending on conditions.
    
    What's included:
    - Hotel pickup and drop-off
    - Professional guide
    - Warm overalls
    - Hot chocolate and pastries
    
    Free rebooking if no aurora seen.
  `,
  keywords: ["tour", "duration", "included", "pickup", "rebooking"],
  updatedAt: Timestamp,
}

// Collection: knowledge_base
{
  id: "kb_photos",
  category: "photos",
  title: "Photo Request Process",
  content: `
    Photos are uploaded to Google Drive within 24-48 hours.
    Photos are organized by date and guide name.
    
    Link format: https://drive.google.com/drive/folders/[FOLDER_ID]
    
    Standard response time: 24 hours
    Busy season response time: 48 hours
  `,
  keywords: ["photo", "pictures", "images", "drive", "folder"],
  updatedAt: Timestamp,
}
```

### Vector Search for Relevant Context

For more advanced retrieval, use Firebase's vector search (or Pinecone/Weaviate):

```javascript
// Future enhancement: Semantic search
async function findRelevantKnowledge(query) {
  // Generate embedding for the query
  const embedding = await openai.embeddings.create({
    model: 'text-embedding-3-small',
    input: query,
  });
  
  // Search knowledge base using vector similarity
  const results = await db.collection('knowledge_base')
    .findNearest('embedding', embedding.data[0].embedding, { limit: 3 });
  
  return results;
}
```

---

## 5. 🔐 Environment Variables & Secrets

### Required for Phase 2

```bash
# Firebase Secrets to add:
firebase functions:secrets:set OPENAI_API_KEY
firebase functions:secrets:set TWILIO_ACCOUNT_SID
firebase functions:secrets:set TWILIO_AUTH_TOKEN
firebase functions:secrets:set TWILIO_WHATSAPP_NUMBER
```

### functions/index.js Updates

```javascript
const { defineSecret } = require('firebase-functions/params');

const OPENAI_API_KEY = defineSecret('OPENAI_API_KEY');
const TWILIO_ACCOUNT_SID = defineSecret('TWILIO_ACCOUNT_SID');
const TWILIO_AUTH_TOKEN = defineSecret('TWILIO_AUTH_TOKEN');
const TWILIO_WHATSAPP_NUMBER = defineSecret('TWILIO_WHATSAPP_NUMBER');

// Use in functions:
exports.generateAiDraft = onDocumentCreated({
  document: 'messages/{messageId}',
  secrets: [OPENAI_API_KEY],
}, async (event) => {
  const openai = new OpenAI({ apiKey: OPENAI_API_KEY.value() });
  // ...
});
```

---

## 6. 📅 Implementation Timeline

### Week 1: Website Chat Widget
- [ ] Create `aurora-chat.js` widget
- [ ] Style with Aurora branding
- [ ] Set up anonymous Firestore sessions
- [ ] Test embed in Wix
- [ ] Connect to Unified Inbox "Website" tab

### Week 2: WhatsApp Integration  
- [ ] Create Twilio account
- [ ] Set up WhatsApp sandbox for testing
- [ ] Implement webhook endpoint
- [ ] Build send reply function
- [ ] Apply for WhatsApp Business verification

### Week 3: AI Draft Responses
- [ ] Add OpenAI integration
- [ ] Create base system prompt
- [ ] Implement draft generation on new messages
- [ ] Build UI for draft review/send
- [ ] Special handling for photo requests

### Week 4: Polish & Knowledge Base
- [ ] Build knowledge base admin UI
- [ ] Fine-tune AI prompts based on testing
- [ ] Add AI analytics (accepted vs rejected drafts)
- [ ] Implement confidence thresholds

---

## 7. 🎯 Success Metrics

| Metric | Target |
|--------|--------|
| AI draft acceptance rate | > 60% |
| Average response time | < 2 hours (vs current ~6 hours) |
| Photo request automation | > 80% auto-handled |
| Customer satisfaction | Maintain current 4.8★ rating |
| Staff time saved | > 50% reduction in email time |

---

## 8. 📝 Notes for Monday

1. **Start with Website Chat** - It's the most contained feature with immediate value
2. **WhatsApp requires business verification** - Start the application early (can take 1-2 weeks)
3. **OpenAI API key needed** - Set up billing and get API key
4. **Test AI drafts on photo inbox first** - Most predictable use case
5. **Consider rate limiting** - AI calls cost money, add limits

Good luck! 🌌

