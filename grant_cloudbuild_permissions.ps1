# Grant permissions to Cloud Build service account via gcloud CLI
# Run these commands if you're authenticated with gcloud

Write-Host "Granting permissions to Cloud Build service account..." -ForegroundColor Yellow

# Grant Artifact Registry Writer
gcloud projects add-iam-policy-binding aurora-viking-staff `
    --member="serviceAccount:975783791718@cloudbuild.gserviceaccount.com" `
    --role="roles/artifactregistry.writer"

# Grant Storage Object Viewer
gcloud projects add-iam-policy-binding aurora-viking-staff `
    --member="serviceAccount:975783791718@cloudbuild.gserviceaccount.com" `
    --role="roles/storage.objectViewer"

# Grant Service Account User
gcloud projects add-iam-policy-binding aurora-viking-staff `
    --member="serviceAccount:975783791718@cloudbuild.gserviceaccount.com" `
    --role="roles/iam.serviceAccountUser"

Write-Host "`nPermissions granted! Wait 1-2 minutes for propagation, then run:" -ForegroundColor Green
Write-Host "firebase deploy --only functions" -ForegroundColor Cyan

