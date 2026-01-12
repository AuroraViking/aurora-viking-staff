# 🌐 Website Chat Widget - Setup Guide

## Overview

The Website Chat Widget is a custom embeddable chat solution that integrates directly with the Aurora Viking Staff app's Unified Inbox.

## What Was Built

### 1. Chat Widget Files (`web/chat-widget/`)
- `aurora-chat.js` - Full source JavaScript widget
- `aurora-chat.min.js` - Minified production version
- `aurora-chat.css` - Styles matching Aurora Viking theme (dark obsidian + teal accents)
- `embed-snippet.html` - Instructions page for embedding on Wix/other sites

### 2. Cloud Functions (in `functions/index.js`)
- `createWebsiteSession` - Creates anonymous chat session for website visitors
- `updateWebsiteSession` - Updates session with page tracking & visitor info
- `sendWebsiteMessage` - Handles incoming messages from the widget
- `updateWebsitePresence` - Tracks online/offline status
- `sendWebsiteChatReply` - Processes staff replies (triggers on outbound message creation)

### 3. Flutter App Updates
- Added `website` channel to `MessageChannel` enum
- Added `WebsiteMetadata` class for website-specific data
- Updated `unified_inbox_screen.dart` - Website tab now active (orange icon)
- Updated `inbox_controller.dart` - Filters for website conversations
- Updated `conversation_screen.dart` - Displays website channel icon

## Deployment Steps

### Step 1: Deploy Cloud Functions
```powershell
cd functions
npm install
firebase deploy --only functions
```

### Step 2: Deploy Web Assets
The chat widget files will be deployed with the Flutter web build:
```powershell
# From project root
flutter build web
firebase deploy --only hosting
```

### Step 3: Test the Widget
After deployment, you can test by visiting:
```
https://aurora-viking-staff.web.app/chat-widget/embed-snippet.html
```

This page shows:
- The embed code to copy
- Step-by-step Wix integration instructions
- Configuration options
- JavaScript API documentation

### Step 4: Add to Wix Website

**For auroraviking.is and auroraviking.com:**

1. Go to Wix Dashboard → Settings → Custom Code
2. Click "+ Add Code"
3. Paste this code:

```html
<!-- Aurora Viking Chat Widget -->
<script>
  window.AURORA_CHAT_CONFIG = {
    projectId: 'aurora-viking-staff',
    position: 'bottom-right',
    primaryColor: '#00E5FF',
    greeting: 'Hi! 👋 Ask us anything about Northern Lights tours!',
    offlineMessage: 'Leave a message and we\'ll get back to you!',
    quickReplies: [
      'Tour availability?',
      'What to wear?',
      'Photo request',
      'Rebooking'
    ]
  };
</script>
<script src="https://aurora-viking-staff.web.app/chat-widget/aurora-chat.min.js" async></script>
```

4. Set placement: "All Pages" → "Body - end"
5. Click "Apply"

## Firestore Collections Used

### `website_sessions`
Stores anonymous visitor sessions:
```javascript
{
  sessionId: "ws_abc123",
  conversationId: "...",
  customerId: "...",
  visitorName: null,        // Collected later
  visitorEmail: null,       // Collected later
  firstPageUrl: "https://...",
  currentPageUrl: "https://...",
  referrer: "...",
  userAgent: "...",
  isOnline: true,
  lastSeen: Timestamp,
  createdAt: Timestamp
}
```

### `conversations` (channel: 'website')
Website conversations appear alongside Gmail/Wix conversations:
```javascript
{
  channel: 'website',
  inboxEmail: 'website',
  channelMetadata: {
    website: {
      sessionId: "ws_abc123",
      firstPageUrl: "..."
    }
  }
}
```

### `messages` (channel: 'website')
Messages from website chat:
```javascript
{
  channel: 'website',
  direction: 'inbound' | 'outbound',
  channelMetadata: {
    website: {
      sessionId: "...",
      pageUrl: "..."
    }
  }
}
```

## Features

| Feature | Status |
|---------|--------|
| Anonymous sessions | ✅ |
| Real-time messaging | ✅ (polling, can upgrade to WebSocket) |
| Message persistence (localStorage) | ✅ |
| Page URL tracking | ✅ |
| Quick reply buttons | ✅ |
| Typing indicators | 🔜 Phase 2 |
| Visitor identification form | 🔜 Phase 2 |
| Read receipts | 🔜 Phase 2 |
| File/image upload | 🔜 Phase 2 |

## Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `projectId` | `'aurora-viking-staff'` | Firebase project |
| `position` | `'bottom-right'` | Widget position |
| `primaryColor` | `'#00E5FF'` | Accent color |
| `greeting` | `'Hi! 👋...'` | Welcome message |
| `offlineMessage` | `'Leave a message...'` | Offline message |
| `quickReplies` | `[...]` | Quick reply buttons |

## JavaScript API

Control the widget programmatically:
```javascript
AuroraChat.open();      // Open chat window
AuroraChat.close();     // Close chat window
AuroraChat.toggle();    // Toggle open/close
AuroraChat.identify('John', 'john@example.com');  // Set visitor info
AuroraChat.destroy();   // Remove widget from page
```

## Next Steps (Phase 2+)

1. **AI Draft Responses** - Auto-generate reply suggestions
2. **Typing indicators** - Show "Staff is typing..."
3. **Read receipts** - Show when messages are seen
4. **File uploads** - Allow image/document sharing
5. **Visitor identification** - Prompt for name/email after first message
6. **WhatsApp Integration** - Similar setup via Twilio

---

Built with 💚 by Aurora Viking

