# Google Sign-In Setup for Photo Upload

This guide will help you configure Google Sign-In so that guides can upload photos directly to Google Drive.

## Step 1: Create OAuth 2.0 Client ID

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your project: `aurora-viking-staff`
3. Navigate to **APIs & Services** > **Credentials**
4. Click **+ CREATE CREDENTIALS** > **OAuth 2.0 Client IDs**
5. Choose **Android** as the application type
6. Fill in the details:
   - **Name**: `Aurora Viking Staff Android`
   - **Package name**: `com.auroraviking.aurora_viking_staff`
   - **SHA-1 certificate fingerprint**: (see step 2)

## Step 2: Get SHA-1 Certificate Fingerprint

Run this command in your project directory:

```bash
# For debug builds
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android

# For release builds (if you have a release keystore)
keytool -list -v -keystore your-release-key.keystore -alias your-key-alias
```

Copy the SHA-1 fingerprint (looks like: `AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD`)

## Step 3: Update AndroidManifest.xml

Add the OAuth client ID to your AndroidManifest.xml:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- ... existing permissions ... -->
    
    <application
        android:label="aurora_viking_staff"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        
        <!-- ... existing activity ... -->
        
        <!-- Google Sign-In Configuration -->
        <meta-data
            android:name="com.google.android.gms.auth.CLIENT_ID"
            android:value="YOUR_OAUTH_CLIENT_ID.apps.googleusercontent.com" />
            
        <!-- ... existing meta-data ... -->
    </application>
</manifest>
```

Replace `YOUR_OAUTH_CLIENT_ID` with the client ID from Step 1.

## Step 4: Enable Google Drive API

1. In Google Cloud Console, go to **APIs & Services** > **Library**
2. Search for "Google Drive API"
3. Click on it and press **Enable**

## Step 5: Configure Drive Permissions

1. Go to [Google Drive](https://drive.google.com/)
2. Sign in as `photo@auroraviking.com`
3. Navigate to the "Norðurljósamyndir" folder
4. Right-click on the "Norðurljósamyndir" folder
5. Click **Share**
6. Add the email address of the Google account that will be used for sign-in
7. Give it **Editor** permissions
8. Click **Send** (no need to notify)

## Step 6: Test the Integration

1. Run the app: `flutter run`
2. Go to the **Photos** tab
3. Click the Google Sign-In button in the app bar
4. Sign in with your Google account
5. Take a photo or select from gallery
6. Upload to Drive

## Troubleshooting

### "Sign-in failed" error
- Check that the OAuth client ID is correct in AndroidManifest.xml
- Verify the SHA-1 fingerprint matches your keystore
- Ensure the Google Drive API is enabled

### "Permission denied" error
- Make sure the Google account has Editor permissions on the Drive folder
- Check that the account is signed in to the correct Google account

### "API not enabled" error
- Enable the Google Drive API in Google Cloud Console
- Wait a few minutes for the API to activate

## Security Notes

- The OAuth client ID is safe to include in your app
- Users will only have access to files they create or are explicitly shared with
- The app only requests `drive.file` scope, which is minimal and secure 