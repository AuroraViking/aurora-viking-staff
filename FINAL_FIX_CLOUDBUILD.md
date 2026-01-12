# Final Fix: Cloud Build Service Account Permissions

The Cloud Build service account needs the **Cloud Build Service Account** role, which is a special role that grants all necessary permissions.

## Steps:

1. Go to IAM & Admin: https://console.cloud.google.com/iam-admin/iam?project=aurora-viking-staff

2. Find the service account: `975783791718@cloudbuild.gserviceaccount.com`

3. Click the **pencil/edit icon** (far right)

4. Click **"+ ADD ANOTHER ROLE"**

5. Add this role:
   - **Cloud Build Service Account** (or search for `roles/cloudbuild.builds.builder`)

6. Click **"SAVE"**

7. Wait 2-3 minutes for permissions to propagate

8. Deploy again:
   ```bash
   firebase deploy --only functions
   ```

## Alternative: All Required Roles

If the Cloud Build Service Account role doesn't work or isn't available, ensure these individual roles are granted:
- ✅ Artifact Registry Writer (already added)
- ✅ Storage Object Viewer (already added)
- ✅ Service Account User (already added)
- ✅ Cloud Build Service Account (roles/cloudbuild.builds.builder) - **ADD THIS**
- ✅ Logs Writer (roles/logging.logWriter) - might be needed
- ✅ Service Account Token Creator (roles/iam.serviceAccountTokenCreator) - might be needed


