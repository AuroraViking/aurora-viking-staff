# Fix Eventarc Service Agent Permissions

## The Problem
Cloud Functions deployment is failing with:
```
Permission denied while using the Eventarc Service Agent
```

This happens when using 2nd generation Cloud Functions with Firestore triggers. The Eventarc Service Agent needs the **Eventarc Service Agent** role.

## Solution: Grant Permission via Google Cloud Console

### Step 1: Open IAM & Admin
1. Go to: https://console.cloud.google.com/iam-admin/iam?project=aurora-viking-staff
2. Make sure you're logged in with the correct Google account

### Step 2: Find or Add the Eventarc Service Agent
The Eventarc Service Agent format is: `service-[PROJECT_NUMBER]@gcp-sa-eventarc.iam.gserviceaccount.com`

Your project number is: `975783791718`
So the service account is: `service-975783791718@gcp-sa-eventarc.iam.gserviceaccount.com`

**Option A: If the service account is already listed:**
1. Find the row with `service-975783791718@gcp-sa-eventarc.iam.gserviceaccount.com`
2. Click the pencil icon (✏️) in the "Actions" column
3. Click "ADD ANOTHER ROLE"
4. Select: `Eventarc Service Agent` (or search for "roles/eventarc.serviceAgent")
5. Click "SAVE"

**Option B: If the service account is NOT listed:**
1. Click "GRANT ACCESS" at the top
2. In "New principals", enter: `service-975783791718@gcp-sa-eventarc.iam.gserviceaccount.com`
3. Click "SELECT A ROLE"
4. Search for and select: `Eventarc Service Agent` (roles/eventarc.serviceAgent)
5. Click "SAVE"

### Step 3: Enable Eventarc API (if not already enabled)
1. Go to: https://console.cloud.google.com/apis/library/eventarc.googleapis.com?project=aurora-viking-staff
2. Click "ENABLE" if it's not already enabled
3. Wait for it to enable (may take 1-2 minutes)

### Step 4: Wait and Deploy Again
After granting the permission:
1. **Wait 2-3 minutes** for permissions to propagate
2. Deploy again:
   ```bash
   firebase deploy --only functions
   ```

## Alternative: Use gcloud CLI (if authenticated)

If you can authenticate with gcloud, you can run:

```bash
# Grant Eventarc Service Agent role
gcloud projects add-iam-policy-binding aurora-viking-staff \
    --member="serviceAccount:service-975783791718@gcp-sa-eventarc.iam.gserviceaccount.com" \
    --role="roles/eventarc.serviceAgent"

# Enable Eventarc API (if needed)
gcloud services enable eventarc.googleapis.com --project=aurora-viking-staff
```

## Note
If you just started using Eventarc, it may take a few minutes for all necessary permissions to be automatically propagated. If the error persists after granting the role and waiting, try:
1. Waiting 5-10 minutes
2. Re-running the deployment
3. Checking the IAM page to confirm the role is assigned

