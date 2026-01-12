# Fix Firestore Permissions for v2 Cloud Functions

## The Problem

v2 Cloud Functions run as Cloud Run services with a different service account than v1 functions. The default compute service account needs explicit Firestore permissions.

**Error you'll see:**
```
❌ Error getting booking details: Error: 7 PERMISSION_DENIED
❌ Error sending notification to admins: Error: 7 PERMISSION_DENIED
```

## Solution: Grant Firestore Permissions

### Option 1: Use PowerShell Script (Recommended)

1. **Authenticate with gcloud** (if not already):
   ```powershell
   gcloud auth login
   ```

2. **Run the script**:
   ```powershell
   .\grant_firestore_permissions.ps1
   ```

### Option 2: Manual Commands

Run these commands in your terminal after authenticating with `gcloud auth login`:

```bash
# Grant to default compute service account (used by Cloud Run)
gcloud projects add-iam-policy-binding aurora-viking-staff \
  --member="serviceAccount:975783791718-compute@developer.gserviceaccount.com" \
  --role="roles/datastore.user"

# Grant to App Engine default service account (backup)
gcloud projects add-iam-policy-binding aurora-viking-staff \
  --member="serviceAccount:aurora-viking-staff@appspot.gserviceaccount.com" \
  --role="roles/datastore.user"
```

### Option 3: Google Cloud Console (Easiest)

1. Go to: https://console.cloud.google.com/iam-admin/iam?project=aurora-viking-staff

2. **Find or add the compute service account:**
   - Look for: `975783791718-compute@developer.gserviceaccount.com`
   - If not found, click "GRANT ACCESS" and add it

3. **Grant the role:**
   - Click the pencil/edit icon next to the service account
   - Click "+ ADD ANOTHER ROLE"
   - Search for and select: `Cloud Datastore User` (roles/datastore.user)
   - Click "SAVE"

4. **Repeat for App Engine service account:**
   - Find or add: `aurora-viking-staff@appspot.gserviceaccount.com`
   - Grant the same `Cloud Datastore User` role

5. **Wait 1-2 minutes** for permissions to propagate

## Verify Permissions

After granting permissions, test the notification functions again. You should see:
- ✅ Functions can read from `cached_bookings` collection
- ✅ Functions can read from `users` collection
- ✅ Notifications are sent successfully

## What This Role Does

`roles/datastore.user` grants:
- Read access to Firestore databases
- Write access to Firestore databases
- All necessary permissions for Cloud Functions to interact with Firestore

This is required because v2 Cloud Functions use Cloud Run, which has different default permissions than v1 functions.


