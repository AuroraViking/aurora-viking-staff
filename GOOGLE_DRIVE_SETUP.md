# Google Drive Setup for Photo Uploads (Secure ADC Method)

This guide will help you set up Google Drive API integration for uploading tour photos to `photo@auroraviking.com` using **Application Default Credentials (ADC)** - the most secure approach that works with organization policies.

## Prerequisites

1. **Google Cloud Project**: You need access to the Aurora Viking Staff Google Cloud project
2. **Google Workspace Account**: Access to `photo@auroraviking.com` Google Drive
3. **Organization Policy Compliance**: This method works with `iam.disableServiceAccountKeyCreation` policies

## Step 1: Enable Google Drive API

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select the `aurora-viking-staff` project
3. Navigate to **APIs & Services** > **Library**
4. Search for "Google Drive API"
5. Click on it and press **Enable**

## Step 2: Set Up Application Default Credentials

### Option A: For Development (Local Testing)

1. Install Google Cloud CLI: https://cloud.google.com/sdk/docs/install
2. Open terminal/command prompt
3. Run the following commands:
   ```bash
   gcloud auth login
   gcloud config set project aurora-viking-staff
   gcloud auth application-default login
   ```
4. This will open a browser window for authentication
5. Sign in with your Google account that has access to the project

### Option B: For Production (Workload Identity Federation)

1. Go to **IAM & Admin** > **Workload Identity Federation**
2. Click **Create Pool**
3. Name it `photo-upload-pool`
4. Add a provider (Google Cloud, AWS, Azure, etc.)
5. Configure the provider settings
6. Create a service account for the pool
7. Grant the service account Drive API permissions

## Step 3: Create Service Account for Drive Access

1. Go to **IAM & Admin** > **Service Accounts**
2. Click **Create Service Account**
3. Fill in the details:
   - **Name**: `photo-upload-service`
   - **Description**: `Service account for photo uploads to Drive`
4. Click **Create and Continue**
5. **Skip role assignment** (we'll handle permissions manually)
6. Click **Done**

## Step 4: Configure Service Account Permissions

1. Go to [Google Drive](https://drive.google.com/)
2. Sign in as `photo@auroraviking.com`
3. Navigate to the "Norðurljósamyndir" folder
4. Right-click on the "Norðurljósamyndir" folder
5. Click **Share**
6. Add the service account email (from step 3)
7. Give it **Editor** permissions
8. Click **Send** (no need to notify)

**Note**: The app will create the proper folder structure: `Norðurljósamyndir/Year/Month/Day Month/Guide Name/` to match your existing organization.

## Step 5: Configure Environment Variables

Since we're using ADC, you don't need to store service account keys in environment variables. The app will automatically use the configured credentials.

However, you can add these optional variables for debugging:
```env
# Optional: For debugging ADC configuration
GOOGLE_APPLICATION_CREDENTIALS=/path/to/your/credentials.json
GOOGLE_CLOUD_PROJECT=aurora-viking-staff
```

## Step 6: Test the Integration

1. Run the app: `flutter run`
2. Go to the **Photos** tab
3. Select some photos
4. Choose a bus and date
5. Click **Upload to Drive**
6. Check the `photo@auroraviking.com` Drive account for the uploaded photos

## Folder Structure

Photos will be organized in the following structure to match your existing setup:
```
Norðurljósamyndir/
├── 2025/
│   ├── December/
│   │   ├── 21 December/
│   │   │   ├── Kolbeinn/
│   │   │   │   ├── 001_IMG_001.jpg
│   │   │   │   ├── 002_IMG_002.jpg
│   │   │   │   └── 003_IMG_003.jpg
│   │   │   └── Jane/
│   │   │       ├── 001_IMG_004.jpg
│   │   │       └── 002_IMG_005.jpg
│   │   └── 22 December/
│   │       └── Mike/
│   │           ├── 001_IMG_006.jpg
│   │           └── 002_IMG_007.jpg
│   └── August/
│       └── 15 August/
│           └── Kolbeinn/
│               ├── 001_IMG_008.jpg
│               └── 002_IMG_009.jpg
└── 2024/
    └── ...
```

**Structure**: `Norðurljósamyndir/Year/Month/Day Month/Guide Name/`

## Troubleshooting

### "Failed to initialize Google Drive API"
- **For Development**: Run `gcloud auth application-default login`
- **For Production**: Check Workload Identity Federation configuration
- Verify the service account has Drive API access

### "Upload failed"
- Check internet connection
- Verify the service account has Editor permissions on the "Norðurljósamyndir" folder
- Check the console logs for specific error messages

### "Permission denied"
- Ensure the service account email is shared with the Drive folder
- Check that the service account has the correct IAM roles

## Security Benefits

✅ **No service account keys** - Uses OAuth tokens instead
✅ **Organization policy compliant** - Works with `iam.disableServiceAccountKeyCreation`
✅ **Automatic credential rotation** - Tokens refresh automatically
✅ **Audit trail** - All access is logged and auditable
✅ **Least privilege** - Service account has minimal permissions

## Support

If you encounter issues:
1. Check the console logs for error messages
2. Verify Application Default Credentials are configured
3. Test the Drive API access manually
4. Contact the development team for assistance 