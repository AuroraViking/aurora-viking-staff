# Debugging Push Notifications

## Current Issue: DEVELOPER_ERROR

The `ConnectionResult{statusCode=DEVELOPER_ERROR}` indicates a Google Play Services configuration issue.

## Common Causes & Solutions

### 1. Missing SHA-1/SHA-256 Fingerprints

**Problem**: Firebase requires your app's signing certificate fingerprints to be registered.

**Solution**:
1. Get your debug keystore SHA-1:
   ```bash
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
   ```
   On Windows:
   ```bash
   keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
   ```

2. Add SHA-1 and SHA-256 to Firebase Console:
   - Go to: https://console.firebase.google.com/project/aurora-viking-staff/settings/general
   - Scroll to "Your apps"
   - Click on your Android app
   - Click "Add fingerprint"
   - Paste both SHA-1 and SHA-256

### 2. google-services.json Missing or Incorrect

**Check**:
- File exists at: `android/app/google-services.json`
- Package name matches: `com.auroraviking.aurora_viking_staff`
- Project ID matches: `aurora-viking-staff`

**Solution**: Download fresh `google-services.json` from Firebase Console if needed.

### 3. Google Play Services Not Available

**Check**: 
- Device/emulator has Google Play Services installed
- Google Play Services is up to date

**Solution**: 
- Use a real device or emulator with Google Play Services
- Update Google Play Services on the device

## Debugging Steps

### Step 1: Check Logs

Look for these log messages in your app:
- `🔔 Initializing notification service...`
- `✅ FirebaseMessaging instance created`
- `🔔 Notification permission status: ...`
- `🔔 FCM Token received: ...`
- `✅ FCM token saved to Firestore successfully`

### Step 2: Verify FCM Token in Firestore

1. Go to Firebase Console > Firestore
2. Check `users/{userId}` collection
3. Look for `fcmToken` field
4. If missing, the DEVELOPER_ERROR is preventing token generation

### Step 3: Test Notification Service Manually

Add this to your app temporarily to test:

```dart
// In a button or after login
final token = await FirebaseMessaging.instance.getToken();
print('FCM Token: $token');
```

If this returns `null` or throws DEVELOPER_ERROR, it's a configuration issue.

### Step 4: Check Cloud Functions Logs

1. Go to: https://console.firebase.google.com/project/aurora-viking-staff/functions/logs
2. Look for errors when booking status changes
3. Check if `sendNotificationToAdmins` is being called

## Testing Notifications

### Test 1: Manual Notification via Firebase Console

1. Go to Firebase Console > Cloud Messaging
2. Send a test message to a specific FCM token
3. If this works, the issue is with the Cloud Functions

### Test 2: Check Booking Status Updates

1. Mark a booking as "arrived" in the app
2. Check Firestore `booking_status` collection
3. Verify the document is updated with `isArrived: true`
4. Check Cloud Functions logs for `onPickupCompleted` execution

### Test 3: Verify Admin Users Have FCM Tokens

1. Check Firestore `users` collection
2. Find users with `role: 'admin'`
3. Verify they have `fcmToken` field
4. If missing, they won't receive notifications

## Quick Fix Checklist

- [ ] SHA-1/SHA-256 fingerprints added to Firebase Console
- [ ] `google-services.json` is in `android/app/`
- [ ] Package name matches in `google-services.json` and `build.gradle.kts`
- [ ] Google Play Services is installed and updated
- [ ] App is running on device/emulator with Google Play Services
- [ ] FCM tokens are being saved to Firestore (check `users` collection)
- [ ] Admin users have `fcmToken` in their user documents
- [ ] Cloud Functions are deployed and running
- [ ] Booking status updates are triggering Cloud Functions

## Next Steps

Once DEVELOPER_ERROR is fixed:
1. FCM tokens should be generated automatically
2. Tokens will be saved to Firestore on login
3. Cloud Functions will send notifications when events occur
4. Check logs to verify each step is working

