# Fix Cloud Functions Storage Permissions

## The Problem
Cloud Functions deployment is failing because the compute service account doesn't have permission to access the storage bucket.

## Solution: Grant Permission via Google Cloud Console

### Step 1: Open IAM & Admin
1. Go to: https://console.cloud.google.com/iam-admin/iam?project=aurora-viking-staff
2. Make sure you're logged in with the correct Google account

### Step 2: Find the Service Account
1. In the IAM table, look for: `975783791718-compute@developer.gserviceaccount.com`
2. If you don't see it, click "GRANT ACCESS" at the top

### Step 3: Grant Storage Object Viewer Role
**Option A: If the service account is already listed:**
1. Find the row with `975783791718-compute@developer.gserviceaccount.com`
2. Click the pencil icon (✏️) in the "Actions" column
3. Click "ADD ANOTHER ROLE"
4. Select: `Storage Object Viewer` (or search for "storage.objectViewer")
5. Click "SAVE"

**Option B: If the service account is NOT listed:**
1. Click "GRANT ACCESS" at the top
2. In "New principals", enter: `975783791718-compute@developer.gserviceaccount.com`
3. Click "SELECT A ROLE"
4. Search for and select: `Storage Object Viewer`
5. Click "SAVE"

### Step 4: Deploy Again
After granting the permission, wait a minute for it to propagate, then run:

```bash
firebase deploy --only functions
```

## Alternative: Use Firebase CLI (if you can authenticate)
If you can authenticate with gcloud, you can run:

```bash
gcloud projects add-iam-policy-binding aurora-viking-staff --member="serviceAccount:975783791718-compute@developer.gserviceaccount.com" --role="roles/storage.objectViewer"
```

But the web console method above is easier and doesn't require command-line authentication.


