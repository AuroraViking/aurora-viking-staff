# Google Sheets Setup for Tour Reports

This guide explains how to set up Google Sheets integration so that tour reports are automatically created in your Google Drive.

## Step 1: Enable Required APIs

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select project: `aurora-viking-staff`
3. Go to **APIs & Services** → **Library**
4. Search for and enable:
   - **Google Sheets API** (if not already enabled)
   - **Google Drive API** (should already be enabled for photo uploads)

## Step 2: Find Your Firebase Service Account Email

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select project: `aurora-viking-staff`
3. Go to **Project Settings** (gear icon) → **Service Accounts** tab
4. Copy the **Service account email** - it looks like:
   ```
   firebase-adminsdk-xxxxx@aurora-viking-staff.iam.gserviceaccount.com
   ```
   Or for App Engine default:
   ```
   aurora-viking-staff@appspot.gserviceaccount.com
   ```

## Step 3: Share the Drive Folder with Service Account

1. Open [Google Drive](https://drive.google.com/) in your browser
2. Navigate to or create a folder called **"Tour Reports"** (or whatever you want)
3. **Right-click** on the folder → **Share**
4. In the "Share with people and groups" field, paste the **service account email** from Step 2
5. Give it **Editor** access (or "Can edit")
6. **IMPORTANT**: Uncheck "Notify people" (service accounts don't need notifications)
7. Click **Share**

## Step 4: Get the Folder ID

1. While viewing the folder in Google Drive, look at the URL in your browser
2. The URL should look like:
   ```
   https://drive.google.com/drive/folders/1ABC123xyz789
   ```
   or
   ```
   https://drive.google.com/drive/u/1/folders/1ABC123xyz789
   ```
3. Copy just the ID part (the long string after `/folders/`):
   ```
   1ABC123xyz789
   ```
4. Open `functions/index.js`
5. Find this line:
   ```javascript
   const DRIVE_FOLDER_ID = 'YOUR_FOLDER_ID_HERE';
   ```
6. Replace `YOUR_FOLDER_ID_HERE` with your actual folder ID:
   ```javascript
   const DRIVE_FOLDER_ID = '1ABC123xyz789';
   ```

## Step 5: Deploy the Function

After updating the folder ID, deploy the function:

```bash
cd functions
firebase deploy --only functions:generateTourReport,functions:generateTourReportManual
```

## Step 6: Test It!

1. Make sure you have pickup assignments for today in Firestore
2. Go to Admin Dashboard → Reports & Analytics
3. Click the **"Test: Generate Today's Report"** button
4. Wait a few seconds for the function to run
5. Check your Google Drive folder - you should see a new spreadsheet!

## Troubleshooting

### "Permission denied" or "Failed to create Google Sheet"

**Solution**: Make sure you shared the folder with the correct service account email:
- Go back to Step 2 and verify the service account email
- Make sure it has **Editor** access (not just Viewer)
- Try unsharing and resharing the folder

### "API not enabled"

**Solution**: Enable the APIs in Google Cloud Console:
- Go to APIs & Services → Library
- Search for "Google Sheets API" and enable it
- Search for "Google Drive API" and enable it

### "Folder not found"

**Solution**: Check the folder ID:
- Make sure you copied ONLY the folder ID (not the full URL)
- The ID should be a long string like `1ABC123xyz789`
- Verify the folder exists in Google Drive

### Function runs but no sheet appears

**Solution**: Check the function logs:
```bash
firebase functions:log
```
Look for error messages related to Google Drive or Sheets API.

## Which Service Account to Use?

Firebase Cloud Functions automatically use one of these service accounts:

1. **App Engine Default Service Account**: 
   - Email: `aurora-viking-staff@appspot.gserviceaccount.com`
   - This is used by default for Cloud Functions

2. **Firebase Admin SDK Service Account**:
   - Email: `firebase-adminsdk-xxxxx@aurora-viking-staff.iam.gserviceaccount.com`
   - Used if you explicitly configure it

**Recommendation**: Share the folder with **both** accounts to be safe, or check the Cloud Function logs to see which one is being used.

## Security Notes

✅ **Secure**: Service accounts use OAuth tokens (no passwords stored)  
✅ **Auditable**: All Drive API access is logged  
✅ **Least Privilege**: Service account only has access to the specific folder you shared  
✅ **Automatic**: Tokens refresh automatically - no manual maintenance needed

