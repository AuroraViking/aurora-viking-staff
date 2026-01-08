# How to Check Cloud Functions Logs for Notifications

## Step 1: Deploy Updated Functions

```bash
cd functions
firebase deploy --only functions:onPickupCompleted,functions:onNoShowMarked
```

## Step 2: Check Cloud Functions Logs

### Option A: Firebase Console (Easiest)

1. Go to: https://console.firebase.google.com/project/aurora-viking-staff/functions/logs
2. Filter by function name: `onPickupCompleted` or `onNoShowMarked`
3. Look for logs with these emojis:
   - `🔔` - Function triggered
   - `📊` - Before/after data
   - `🔍` - Status checks
   - `✅` - Success messages
   - `⚠️` - Warnings

### Option B: Firebase CLI

```bash
# View recent logs for pickup completed
firebase functions:log --only onPickupCompleted

# View recent logs for no-show
firebase functions:log --only onNoShowMarked

# View all function logs
firebase functions:log
```

## Step 3: Test and Check Logs

1. Mark a booking as "arrived" in the app
2. Immediately check the Cloud Functions logs
3. You should see:
   - `🔔 onPickupCompleted triggered for document: 2026-01-08_74522227`
   - `📊 Before data: ...`
   - `📊 After data: ...`
   - `🔍 Checking pickup status: wasArrived=..., isNowArrived=...`
   - `✅ Pickup completed detected...` (if condition met)
   - `📤 Preparing to send notification...`
   - `👥 Found X users in database`
   - `📱 Found X FCM tokens...`

## What to Look For

### If you see "🔔 onPickupCompleted triggered":
✅ Function is being triggered correctly

### If you see "⚠️ Document ID doesn't have enough parts":
❌ Document ID format issue - check the parsing logic

### If you see "ℹ️ Pickup status did not change from false to true":
❌ The document already had `isArrived: true` or the condition wasn't met

### If you see "⚠️ No FCM tokens found for users":
❌ Users don't have FCM tokens saved - check Firestore `users` collection

### If you see "✅ Notification sent to X user(s)":
✅ Notifications were sent successfully!

## Troubleshooting

### No logs at all?
- Check if the function is deployed: `firebase functions:list`
- Verify the function name matches: `onPickupCompleted`
- Check if Firestore triggers are enabled

### Function triggered but no notification?
- Check if users have `fcmToken` in Firestore
- Check if FCM tokens are valid (not expired)
- Check device notification settings

### Function not triggered?
- Verify the document path: `booking_status/{documentId}`
- Check if the document was actually created/updated in Firestore
- Verify the function is listening to the correct collection

