# Fix Compute Service Account Issue

The error shows that the default compute service account `975783791718-compute@developer.gserviceaccount.com` doesn't exist.

## Solution: Enable Compute Engine API

The compute service account is automatically created when you enable the Compute Engine API.

### Steps:

1. **Enable Compute Engine API:**
   - Go to: https://console.cloud.google.com/apis/library/compute.googleapis.com?project=aurora-viking-staff
   - Click the blue "ENABLE" button
   - Wait for it to enable (may take 1-2 minutes)

2. **Verify the service account was created:**
   - Go to: https://console.cloud.google.com/iam-admin/serviceaccounts?project=aurora-viking-staff
   - Look for: `975783791718-compute@developer.gserviceaccount.com`
   - If it appears, proceed to step 3

3. **Grant Storage Object Viewer permission:**
   - Go to: https://console.cloud.google.com/iam-admin/iam?project=aurora-viking-staff
   - Find or add: `975783791718-compute@developer.gserviceaccount.com`
   - Grant it the `Storage Object Viewer` role
   - (If you already did this, that's fine - just make sure it's there)

4. **Deploy again:**
   ```bash
   firebase deploy --only functions
   ```

## Alternative: If Compute Engine API can't be enabled

If you don't want to enable Compute Engine API, we can modify the function to use a different service account. But enabling Compute Engine API is the standard solution for Cloud Functions.

