# Fix Cloud Build Service Account Permissions

The build is failing because the Cloud Build service account needs additional permissions.

## The Problem

2nd Gen Cloud Functions use Cloud Build to build container images. The Cloud Build service account needs permissions to:
- Access Artifact Registry (to push container images)
- Access Storage (to read source code)

## Solution: Grant Permissions via Google Cloud Console

### Step 1: Find the Cloud Build Service Account

The Cloud Build service account format is: `[PROJECT_NUMBER]@cloudbuild.gserviceaccount.com`

Your project number is: `975783791718`
So the service account is: `975783791718@cloudbuild.gserviceaccount.com`

### Step 2: Grant Permissions

1. Go to IAM & Admin: https://console.cloud.google.com/iam-admin/iam?project=aurora-viking-staff

2. Find or add the service account: `975783791718@cloudbuild.gserviceaccount.com`

3. Grant these roles:
   - **Artifact Registry Writer** (or `roles/artifactregistry.writer`)
   - **Storage Object Viewer** (or `roles/storage.objectViewer`)
   - **Service Account User** (or `roles/iam.serviceAccountUser`) - if not already granted

### Step 3: Deploy Again

After granting permissions, deploy again:

```bash
firebase deploy --only functions
```

## Alternative: Use gcloud CLI (if authenticated)

If you can authenticate with gcloud, you can run:

```bash
gcloud projects add-iam-policy-binding aurora-viking-staff --member="serviceAccount:975783791718@cloudbuild.gserviceaccount.com" --role="roles/artifactregistry.writer"

gcloud projects add-iam-policy-binding aurora-viking-staff --member="serviceAccount:975783791718@cloudbuild.gserviceaccount.com" --role="roles/storage.objectViewer"
```

But the web console method is easier.


