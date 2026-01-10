# 🌌 Aurora Viking Unified Inbox - Complete Architecture & Roadmap

> **Generated**: January 10, 2026
> **Author**: AI Architecture Analysis
> **Status**: Phase 1 Complete ✅ | Phases 2-4 Ready for Implementation

---

## 📊 Current State Summary

### Phase 1 MVP - COMPLETE ✅

| Component | Status | Notes |
|-----------|--------|-------|
| Gmail OAuth Integration | ✅ | Connected to info@auroraviking.com |
| Polling (every 2 min) | ✅ | Cloud Scheduler via `pollGmailInbox` |
| Email Body Extraction | ✅ | Handles nested multipart MIME |
| Auto-send Replies | ✅ | Firestore trigger `onOutboundMessageCreated` |
| Customer Records | ✅ | Auto-created from sender email |
| Conversation Threading | ✅ | By Gmail threadId |
| Booking Detection | ✅ | Regex for AV-XXXXX patterns |
| Admin Inbox UI | ✅ | Channel filters, unread badges |
| Message Composition | ✅ | Reply from conversation screen |

---

## 🧠 Phase 2: AI Draft Responses

### Overview
Use Claude AI to analyze incoming messages and generate intelligent draft responses that staff can review, edit, and send.

### Architecture

```
┌─────────────────────┐
│  New Email Arrives  │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ processGmailMessage │ (existing)
└──────────┬──────────┘
           │
           ▼
┌─────────────────────────────────────┐
│      generateAiDraft (NEW)          │
│  - Triggered on message creation    │
│  - Calls Claude API with context    │
│  - Stores draft in message doc      │
└──────────┬──────────────────────────┘
           │
           ▼
┌─────────────────────┐
│    Flutter App      │
│  - Shows AI draft   │
│  - Staff edits/sends│
└─────────────────────┘
```

### Implementation Steps

#### 2.1 Add Claude API Integration

**File: `functions/index.js`**

```javascript
// Add to imports
const Anthropic = require('@anthropic-ai/sdk');

// Add secret
// firebase functions:secrets:set ANTHROPIC_API_KEY

// AI Draft Generation Function
exports.generateAiDraft = onDocumentCreated(
  {
    document: 'messages/{messageId}',
    region: 'us-central1',
    secrets: ['ANTHROPIC_API_KEY'],
  },
  async (event) => {
    const messageData = event.data.data();
    
    // Only generate drafts for inbound messages
    if (messageData.direction !== 'inbound') return;
    
    // Get context
    const customer = await getCustomerContext(messageData.customerId);
    const bookings = await getRelatedBookings(messageData.detectedBookingNumbers);
    const conversationHistory = await getConversationHistory(messageData.conversationId);
    
    // Generate AI draft
    const draft = await generateDraft({
      message: messageData,
      customer,
      bookings,
      history: conversationHistory,
    });
    
    // Save draft
    await db.collection('messages').doc(event.params.messageId).update({
      aiDraft: {
        content: draft.content,
        confidence: draft.confidence,
        suggestedTone: draft.tone,
        generatedAt: admin.firestore.FieldValue.serverTimestamp(),
        reasoning: draft.reasoning,
      },
      status: 'draftReady',
    });
  }
);

async function generateDraft({ message, customer, bookings, history }) {
  const anthropic = new Anthropic({
    apiKey: process.env.ANTHROPIC_API_KEY,
  });
  
  const systemPrompt = `You are a helpful customer service agent for Aurora Viking, 
an aurora borealis and Northern Lights tour company based in Iceland.

COMPANY INFO:
- Tours depart from Reykjavik at various times
- Pickup is from hotels/bus stops in Reykjavik
- Tours run weather-dependent (aurora visibility)
- Refunds/reschedules handled through Bokun booking system

TONE: Friendly, professional, helpful. Use customer's name when possible.

BOOKING CONTEXT:
${bookings.length > 0 ? bookings.map(b => `
- Booking ${b.confirmationCode}: ${b.customerFullName}
  Date: ${b.pickupTime}
  Guests: ${b.numberOfGuests}
  Pickup: ${b.pickupPlaceName}
  Status: ${b.status}
`).join('\n') : 'No bookings found for this customer'}

CUSTOMER HISTORY:
- Past interactions: ${customer.pastInteractions}
- VIP Status: ${customer.vipStatus ? 'Yes' : 'No'}
- Common requests: ${customer.commonRequests.join(', ') || 'None recorded'}
`;

  const response = await anthropic.messages.create({
    model: 'claude-sonnet-4-20250514',
    max_tokens: 1024,
    system: systemPrompt,
    messages: [
      ...history.map(msg => ({
        role: msg.direction === 'inbound' ? 'user' : 'assistant',
        content: msg.content,
      })),
      {
        role: 'user',
        content: `Customer email (${message.subject}):\n\n${message.content}\n\nGenerate a helpful response.`,
      }
    ],
  });
  
  return {
    content: response.content[0].text,
    confidence: 0.85, // Can be enhanced with classification
    tone: 'friendly',
    reasoning: 'Standard response based on context',
  };
}
```

#### 2.2 Update Flutter Message Model

The model already has `aiDraft` field! Just ensure it's displayed:

**File: `lib/modules/inbox/conversation_screen.dart`**

```dart
// Add AI Draft panel above the message input
if (controller.selectedConversation?.hasAiDraft == true)
  _buildAiDraftPanel(controller),

Widget _buildAiDraftPanel(InboxController controller) {
  final draft = controller.currentAiDraft;
  if (draft == null) return SizedBox.shrink();
  
  return Container(
    margin: EdgeInsets.all(12),
    padding: EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.blue.withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.blue.withOpacity(0.3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.blue, size: 16),
            SizedBox(width: 8),
            Text('AI Draft', style: TextStyle(fontWeight: FontWeight.bold)),
            Spacer(),
            Text('${(draft.confidence * 100).toInt()}% confident',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        SizedBox(height: 8),
        Text(draft.content),
        SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton.icon(
              icon: Icon(Icons.edit),
              label: Text('Use & Edit'),
              onPressed: () => _useDraft(draft.content),
            ),
            SizedBox(width: 8),
            OutlinedButton(
              child: Text('Ignore'),
              onPressed: () => controller.dismissDraft(),
            ),
          ],
        ),
      ],
    ),
  );
}
```

#### 2.3 Estimated Effort
- **Backend**: 4-6 hours
- **Frontend**: 2-3 hours
- **Testing**: 2 hours
- **Total**: ~1 day

---

## 🎯 Phase 3: Bokun Action Suggestions

### Overview
AI analyzes messages to detect booking-related requests and suggests specific Bokun actions (reschedule, change pickup, cancel, etc.)

### Common Customer Requests Detected

| Intent | Example | Suggested Action |
|--------|---------|------------------|
| **Reschedule** | "Can we change to tomorrow?" | Change booking date |
| **Change Pickup** | "Actually pickup from Hilton" | Update pickup location |
| **Add Guests** | "My friend wants to join" | Modify participant count |
| **Cancel** | "We need to cancel" | Process cancellation |
| **Weather Query** | "Will tonight be good?" | Provide aurora forecast |
| **Time Query** | "What time is pickup?" | Confirm pickup details |
| **General Info** | "What should we wear?" | Standard info response |

### Architecture

```
┌─────────────────────────────────┐
│       Claude Analysis           │
│  - Intent classification        │
│  - Entity extraction            │
│  - Confidence scoring           │
└──────────────┬──────────────────┘
               │
               ▼
┌─────────────────────────────────┐
│    Suggested Action Created     │
│  - Type: reschedule/cancel/etc  │
│  - Related booking ID           │
│  - Proposed changes             │
│  - Human approval required      │
└──────────────┬──────────────────┘
               │
               ▼
┌─────────────────────────────────┐
│      Admin Reviews Action       │
│  ✅ Approve → Execute on Bokun  │
│  ❌ Reject → Dismiss suggestion │
│  ✏️ Modify → Edit then approve  │
└─────────────────────────────────┘
```

### Implementation Steps

#### 3.1 Intent Classification

```javascript
async function classifyIntent(message, bookings) {
  const response = await anthropic.messages.create({
    model: 'claude-sonnet-4-20250514',
    max_tokens: 500,
    system: `Classify the customer's intent. Return JSON only.
    
Possible intents:
- RESCHEDULE: Customer wants to change tour date
- CHANGE_PICKUP: Customer wants different pickup location
- ADD_GUESTS: Customer wants to add more people
- REMOVE_GUESTS: Customer wants fewer people
- CANCEL: Customer wants to cancel
- WEATHER_QUERY: Asking about aurora/weather
- BOOKING_INFO: Asking about their booking details
- GENERAL_INFO: General question about tours
- OTHER: Doesn't fit categories

Return format:
{
  "intent": "INTENT_TYPE",
  "confidence": 0.0-1.0,
  "entities": {
    "newDate": "2026-01-15" (if reschedule),
    "newPickup": "Hotel name" (if change_pickup),
    "guestChange": +2 or -1 (if add/remove guests)
  },
  "relatedBookingId": "AV-12345" (if detected)
}`,
    messages: [{
      role: 'user',
      content: `Customer message: ${message.content}
      
Known bookings: ${JSON.stringify(bookings)}`,
    }],
  });
  
  return JSON.parse(response.content[0].text);
}
```

#### 3.2 Create Suggested Action

```javascript
async function createSuggestedAction(messageId, intent, booking) {
  const actionData = {
    messageId,
    type: intent.intent,
    bookingId: intent.relatedBookingId,
    confidence: intent.confidence,
    currentState: {
      date: booking.pickupTime,
      pickup: booking.pickupPlaceName,
      guests: booking.numberOfGuests,
    },
    proposedState: {
      date: intent.entities.newDate || booking.pickupTime,
      pickup: intent.entities.newPickup || booking.pickupPlaceName,
      guests: booking.numberOfGuests + (intent.entities.guestChange || 0),
    },
    status: 'pending', // pending, approved, rejected, executed
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  
  await db.collection('suggestedActions').add(actionData);
}
```

#### 3.3 Flutter UI for Action Approval

```dart
Widget _buildSuggestedActionCard(SuggestedAction action) {
  return Card(
    color: Colors.orange.withOpacity(0.1),
    child: Padding(
      padding: EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb, color: Colors.orange),
              SizedBox(width: 8),
              Text('Suggested: ${action.type.displayName}',
                style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          SizedBox(height: 8),
          _buildChangeComparison(action),
          SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                icon: Icon(Icons.check),
                label: Text('Approve & Execute'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                ),
                onPressed: () => _executeAction(action),
              ),
              SizedBox(width: 8),
              OutlinedButton(
                child: Text('Reject'),
                onPressed: () => _rejectAction(action),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
```

#### 3.4 Bokun API Integration for Actions

```javascript
// Execute approved action on Bokun
exports.executeBokunAction = onCall(
  {
    region: 'us-central1',
    secrets: ['BOKUN_ACCESS_KEY', 'BOKUN_SECRET_KEY'],
  },
  async (request) => {
    const { actionId } = request.data;
    
    const actionDoc = await db.collection('suggestedActions').doc(actionId).get();
    const action = actionDoc.data();
    
    if (action.status !== 'approved') {
      throw new Error('Action not approved');
    }
    
    // Execute based on type
    switch (action.type) {
      case 'RESCHEDULE':
        await bokunReschedule(action.bookingId, action.proposedState.date);
        break;
      case 'CHANGE_PICKUP':
        await bokunChangePickup(action.bookingId, action.proposedState.pickup);
        break;
      case 'CANCEL':
        await bokunCancel(action.bookingId);
        break;
      // etc.
    }
    
    await actionDoc.ref.update({
      status: 'executed',
      executedAt: admin.firestore.FieldValue.serverTimestamp(),
      executedBy: request.auth.uid,
    });
    
    return { success: true };
  }
);
```

#### 3.5 Estimated Effort
- **Intent Classification**: 4-6 hours
- **Bokun Action APIs**: 6-8 hours (research Bokun API for modifications)
- **Flutter UI**: 4-6 hours
- **Testing**: 4 hours
- **Total**: ~2-3 days

---

## 🤖 Phase 4: Full Automation

### Overview
Enable fully automated responses for common queries with human approval workflow for high-risk actions.

### Automation Tiers

| Tier | Confidence | Action |
|------|------------|--------|
| **Auto-Send** | >95% + Simple query | Send immediately |
| **Auto-Draft** | 80-95% | Draft ready, notify staff |
| **Human Review** | <80% or booking change | Require approval |
| **Escalate** | Complex/angry | Flag for senior staff |

### Implementation

#### 4.1 Automation Rules Engine

```javascript
const AUTOMATION_RULES = {
  // Auto-send rules (no human needed)
  autoSend: [
    {
      intent: 'WEATHER_QUERY',
      minConfidence: 0.95,
      conditions: ['!containsComplaint'],
    },
    {
      intent: 'BOOKING_INFO',
      minConfidence: 0.95,
      conditions: ['hasMatchingBooking'],
    },
    {
      intent: 'GENERAL_INFO',
      minConfidence: 0.95,
      conditions: ['isStandardQuestion'],
    },
  ],
  
  // Always require human
  humanRequired: [
    'CANCEL',
    'REFUND',
    'COMPLAINT',
    'RESCHEDULE',  // Phase 4+ could auto-approve
  ],
};

async function processAutomation(message, aiAnalysis) {
  const tier = determineAutomationTier(aiAnalysis);
  
  switch (tier) {
    case 'AUTO_SEND':
      await sendAutomatedResponse(message, aiAnalysis.draftResponse);
      await logAutomation(message.id, 'auto_sent');
      break;
      
    case 'AUTO_DRAFT':
      await saveDraft(message.id, aiAnalysis.draftResponse);
      await notifyStaff('New draft ready for review');
      break;
      
    case 'HUMAN_REVIEW':
      await flagForReview(message.id, aiAnalysis);
      break;
      
    case 'ESCALATE':
      await escalateToSenior(message.id, aiAnalysis);
      await notifyUrgent('Customer needs immediate attention');
      break;
  }
}
```

#### 4.2 Staff Dashboard for Automation

```dart
// Show automation stats
class AutomationDashboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildStatCard('Auto-handled today', '23'),
        _buildStatCard('Pending review', '5'),
        _buildStatCard('Escalated', '1'),
        _buildStatCard('Average response time', '< 2 min'),
        
        // Recent auto-responses for audit
        Text('Recent Auto-Responses'),
        ListView.builder(
          itemCount: autoResponses.length,
          itemBuilder: (ctx, i) => _buildAutoResponseTile(autoResponses[i]),
        ),
      ],
    );
  }
}
```

#### 4.3 Estimated Effort
- **Rules Engine**: 4-6 hours
- **Automation Logic**: 6-8 hours
- **Dashboard**: 4 hours
- **Testing & Tuning**: 8 hours
- **Total**: ~3-4 days

---

## 📋 Data Models Reference

### Current Models (Already Implemented)

```dart
// Message (lib/core/models/messaging/message.dart)
class Message {
  String id;
  String conversationId;
  String customerId;
  MessageChannel channel;        // gmail, wix, whatsapp
  MessageDirection direction;    // inbound, outbound
  String content;
  DateTime timestamp;
  String? subject;
  ChannelMetadata channelMetadata;
  List<String> bookingIds;
  List<String> detectedBookingNumbers;
  AiDraft? aiDraft;              // ← Phase 2
  List<SuggestedAction> suggestedActions;  // ← Phase 3
  MessageStatus status;          // pending, draftReady, responded, autoHandled
  MessagePriority priority;
}

// Customer (lib/core/models/messaging/customer.dart)
class Customer {
  String id;
  String name;
  String? email;
  String? phone;
  CustomerChannels channels;
  int totalBookings;
  List<String> upcomingBookings;
  int pastInteractions;
  bool vipStatus;
  List<String> commonRequests;   // ← Phase 3: Learn patterns
}

// Conversation (lib/core/models/messaging/conversation.dart)
class Conversation {
  String id;
  String customerId;
  String channel;
  String? subject;
  List<String> bookingIds;
  ConversationStatus status;     // active, resolved, archived
  int unreadCount;
}
```

### New Models Needed

```dart
// SuggestedAction (Phase 3)
class SuggestedAction {
  String id;
  String messageId;
  String type;           // RESCHEDULE, CHANGE_PICKUP, CANCEL, etc.
  String bookingId;
  double confidence;
  Map<String, dynamic> currentState;
  Map<String, dynamic> proposedState;
  String status;         // pending, approved, rejected, executed
  String? executedBy;
  DateTime? executedAt;
  String? rejectionReason;
}

// AutomationLog (Phase 4)
class AutomationLog {
  String id;
  String messageId;
  String action;         // auto_sent, auto_drafted, escalated
  String tier;           // AUTO_SEND, AUTO_DRAFT, HUMAN_REVIEW
  double confidence;
  String? overriddenBy;
  DateTime timestamp;
}
```

---

## 🔧 Required Infrastructure

### API Keys & Secrets

```bash
# Already configured
firebase functions:secrets:set GMAIL_CLIENT_ID     ✅
firebase functions:secrets:set GMAIL_CLIENT_SECRET ✅
firebase functions:secrets:set BOKUN_ACCESS_KEY    ✅
firebase functions:secrets:set BOKUN_SECRET_KEY    ✅

# Phase 2: Add Claude API
firebase functions:secrets:set ANTHROPIC_API_KEY

# Optional: WhatsApp integration (future)
firebase functions:secrets:set WHATSAPP_TOKEN
firebase functions:secrets:set WHATSAPP_PHONE_ID
```

### Firestore Indexes Needed

```json
// Add to firestore.indexes.json
{
  "collectionGroup": "suggestedActions",
  "fields": [
    { "fieldPath": "messageId", "order": "ASCENDING" },
    { "fieldPath": "status", "order": "ASCENDING" }
  ]
},
{
  "collectionGroup": "automationLogs",
  "fields": [
    { "fieldPath": "timestamp", "order": "DESCENDING" }
  ]
}
```

### NPM Dependencies

```json
// Add to functions/package.json
{
  "dependencies": {
    "@anthropic-ai/sdk": "^0.30.0"
  }
}
```

---

## 📈 Success Metrics

### Phase 2 KPIs
- [ ] AI draft acceptance rate > 60%
- [ ] Average time to respond reduced by 50%
- [ ] Staff satisfaction score

### Phase 3 KPIs
- [ ] Action suggestion accuracy > 80%
- [ ] Bokun action execution success rate
- [ ] Time saved on booking modifications

### Phase 4 KPIs
- [ ] Auto-response rate for simple queries > 70%
- [ ] Customer satisfaction maintained
- [ ] Escalation rate < 5%

---

## 🚀 Recommended Implementation Order

### Week 1: Phase 2 Foundation
1. Set up Anthropic API key
2. Create basic draft generation
3. Add draft display in UI
4. Test with real emails

### Week 2: Phase 2 Refinement + Phase 3 Start
1. Tune prompts based on feedback
2. Add intent classification
3. Create suggestedActions collection
4. Basic action UI

### Week 3: Phase 3 Completion
1. Bokun API research for modifications
2. Implement action execution
3. Full approval workflow
4. Testing

### Week 4: Phase 4 (Optional)
1. Automation rules engine
2. Dashboard for monitoring
3. Gradual rollout
4. Fine-tuning

---

## 💡 Quick Wins for Monday

1. **Add Anthropic API Key**
   ```bash
   firebase functions:secrets:set ANTHROPIC_API_KEY
   ```

2. **Test Classification Manually**
   - Create a simple Cloud Function to test intent classification
   - Verify it correctly identifies reschedule vs. cancel vs. info requests

3. **UI Polish**
   - Add loading states for AI drafts
   - Show "Analyzing..." while Claude processes

4. **Notification for New Messages**
   - Push notification when new email arrives
   - Badge in admin dashboard

---

## 📝 Notes

### Bokun API Considerations
- Bokun API may have rate limits
- Some modifications require specific API endpoints
- May need to cache booking data to reduce API calls
- Consider webhook for real-time booking updates

### Claude API Costs (Estimated)
- Claude Sonnet: ~$0.003 per 1K tokens
- Average email: ~500 tokens input + 300 tokens output
- Cost per email: ~$0.0024
- 1000 emails/month: ~$2.40

### WhatsApp Integration (Future)
- Requires Meta Business verification
- Different message format than email
- Real-time webhooks (not polling)
- Rich message types (buttons, lists)

---

*This document will be updated as implementation progresses.*

