# Grant permissions to Eventarc Service Agent via gcloud CLI
# Run these commands if you're authenticated with gcloud

Write-Host "Granting permissions to Eventarc Service Agent..." -ForegroundColor Yellow

# Grant Eventarc Service Agent role
gcloud projects add-iam-policy-binding aurora-viking-staff `
    --member="serviceAccount:service-975783791718@gcp-sa-eventarc.iam.gserviceaccount.com" `
    --role="roles/eventarc.serviceAgent"

# Enable Eventarc API (if not already enabled)
Write-Host "`nEnabling Eventarc API..." -ForegroundColor Yellow
gcloud services enable eventarc.googleapis.com --project=aurora-viking-staff

Write-Host "`n✅ Permissions granted! Wait 2-3 minutes for propagation, then run:" -ForegroundColor Green
Write-Host "firebase deploy --only functions" -ForegroundColor Cyan

