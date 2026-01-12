# 🌐 Website Chat Widget - Complete Setup Guide

## Overview

The Website Chat Widget is a custom embeddable chat solution that integrates directly with the Aurora Viking Staff app's Unified Inbox. It uses **Firebase Anonymous Authentication** for secure API access.

---

## ✅ Current Status

| Component | Status |
|-----------|--------|
| Chat Widget JS | ✅ Deployed with Firebase Auth |
| Chat Widget CSS | ✅ Modern sci-fi Aurora theme |
| Cloud Functions | ✅ Auth-verified endpoints |
| Firebase Anonymous Auth | ⚠️ **Must be enabled in Firebase Console** |

---

## 🚀 Quick Setup for Production (Wix)

### Step 1: Enable Anonymous Auth in Firebase

1. Go to: https://console.firebase.google.com/project/aurora-viking-staff/authentication/providers
2. Scroll down to find **"Anonymous"** (not Google!)
3. Click on it and toggle **Enable**
4. Click **Save**

### Step 2: Update Wix Custom Code

Replace your current chat widget code in Wix with this:

```html
<!-- Aurora Viking Chat Widget v2 -->
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
<script src="https://aurora-viking-staff.web.app/chat-widget/aurora-chat.js" async></script>
```

### Step 3: Configure Placement

- **Add Code to Pages:** All Pages
- **Place Code in:** Body - end

---

## 📁 Files Reference

| File | Purpose |
|------|---------|
| `web/chat-widget/aurora-chat.js` | Main widget with Firebase Auth |
| `web/chat-widget/aurora-chat.css` | Modern sci-fi styling |
| `web/chat-widget/embed-snippet.html` | Instructions and demo page |
| `functions/index.js` | Cloud Functions with auth verification |

---

## 🔐 How Authentication Works

1. **Widget loads** → Firebase SDK initializes
2. **Anonymous sign-in** → User gets temporary auth token
3. **API calls** → Token included in `Authorization: Bearer <token>` header
4. **Cloud Functions** → Verify token with `admin.auth().verifyIdToken()`

This approach:
- ✅ Bypasses GCP org policy blocking public functions
- ✅ More secure than fully public endpoints
- ✅ Provides session tracking via Firebase Auth UID

---

## 🔧 Cloud Functions

All website chat functions now require authentication:

| Function | Purpose |
|----------|---------|
| `createWebsiteSession` | Creates new chat session |
| `updateWebsiteSession` | Updates page tracking, visitor info |
| `sendWebsiteMessage` | Handles messages from widget |
| `updateWebsitePresence` | Tracks online/offline status |
| `sendWebsiteChatReply` | Firestore trigger for staff replies |

---

## 🎨 Styling Features

The widget uses a modern sci-fi Aurora theme:

- **Glassmorphism** - Frosted glass effect
- **Aurora gradients** - Shifting cyan/teal/green colors
- **Glow effects** - Neon-style button glows
- **Smooth animations** - Spring-based transitions
- **Dark theme** - Matches Aurora Viking branding

---

## 📊 Firestore Collections

### `website_sessions`
```javascript
{
  sessionId: "ws_abc123",
  conversationId: "...",
  customerId: "...",
  visitorName: null,        // Collected later
  visitorEmail: null,       // Collected later
  firstPageUrl: "https://...",
  currentPageUrl: "https://...",
  isOnline: true,
  lastSeen: Timestamp,
  createdAt: Timestamp
}
```

### `conversations` (channel: 'website')
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

---

## 🔧 JavaScript API

Control the widget programmatically:

```javascript
// Open the chat
AuroraChat.open();

// Close the chat
AuroraChat.close();

// Toggle open/close
AuroraChat.toggle();

// Identify a visitor (e.g., after they book)
AuroraChat.identify('John Doe', 'john@example.com');

// Remove the widget completely
AuroraChat.destroy();
```

---

## ⚙️ Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `projectId` | `'aurora-viking-staff'` | Firebase project |
| `position` | `'bottom-right'` | Widget position |
| `primaryColor` | `'#00E5FF'` | Accent color |
| `greeting` | `'Hi! 👋...'` | Welcome message |
| `offlineMessage` | `'Leave a message...'` | Offline message |
| `quickReplies` | `[...]` | Quick reply buttons |

---

## 🧪 Testing

### Test Page
https://aurora-viking-staff.web.app/chat-widget/embed-snippet.html

### Verify in Firebase Console
1. Check **Authentication > Users** for anonymous users
2. Check **Firestore > website_sessions** for new sessions
3. Check **Firestore > messages** for chat messages

### Check Function Logs
```powershell
firebase functions:log --only createWebsiteSession,sendWebsiteMessage
```

---

## 🔜 Future Enhancements

- [ ] Typing indicators (real-time)
- [ ] Read receipts
- [ ] File/image uploads  
- [ ] Visitor identification form
- [ ] AI draft responses integration

---

## 🆘 Troubleshooting

### "Unable to connect" error
- Verify Anonymous Auth is enabled in Firebase Console
- Check browser console for specific errors

### Old styling showing
- Hard refresh the page (Ctrl+F5)
- Clear browser cache

### Messages not appearing in app
- Check Firestore for new documents
- Verify Cloud Functions are deployed

---

*Last updated: January 12, 2026*
