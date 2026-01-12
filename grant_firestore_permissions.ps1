# Grant Firestore permissions to Cloud Run service account for v2 Cloud Functions
# Run these commands after authenticating with gcloud

Write-Host "Granting Firestore permissions to Cloud Run service accounts..." -ForegroundColor Yellow
Write-Host ""

# Grant to default compute service account (used by Cloud Run)
Write-Host "Granting roles/datastore.user to compute service account..." -ForegroundColor Cyan
gcloud projects add-iam-policy-binding aurora-viking-staff `
    --member="serviceAccount:975783791718-compute@developer.gserviceaccount.com" `
    --role="roles/datastore.user"

# Grant to App Engine default service account (backup)
Write-Host ""
Write-Host "Granting roles/datastore.user to App Engine service account..." -ForegroundColor Cyan
gcloud projects add-iam-policy-binding aurora-viking-staff `
    --member="serviceAccount:aurora-viking-staff@appspot.gserviceaccount.com" `
    --role="roles/datastore.user"

Write-Host ""
Write-Host "✅ Permissions granted! Wait 1-2 minutes for propagation, then test notifications." -ForegroundColor Green


