# Deploying Firebase Cloud Functions for Bokun API

This guide explains how to set up and deploy the Firebase Cloud Function that securely proxies Bokun API requests.

## Why Cloud Functions?

The Bokun API keys (`BOKUN_ACCESS_KEY` and `BOKUN_SECRET_KEY`) cannot be exposed in the web frontend because:
- Anyone can view the source code and network requests
- API keys would be visible in the browser's developer tools
- This is a security risk

Cloud Functions keep the API keys secure on the server side.

## Prerequisites

1. Firebase CLI installed: `npm install -g firebase-tools`
2. Node.js 18+ installed
3. Authenticated with Firebase: `firebase login`

## Setup Steps

### 1. Install Dependencies

```bash
cd functions
npm install
cd ..
```

### 2. Create .env File for Local Development

Create `functions/.env` file with your Bokun API keys:

```bash
# In functions directory
BOKUN_ACCESS_KEY=your_actual_bokun_access_key_here
BOKUN_SECRET_KEY=your_actual_bokun_secret_key_here
```

**Important:** 
- Replace the placeholder values with your actual Bokun API credentials from your root `.env` file
- The `functions/.env` file is gitignored and won't be committed
- This file is used for local emulator testing only

### 3. Set Production Secrets (Required for Deployment)

For production, use Firebase Secret Manager (recommended):

```bash
firebase functions:secrets:set BOKUN_ACCESS_KEY
# When prompted, paste your actual Bokun access key

firebase functions:secrets:set BOKUN_SECRET_KEY
# When prompted, paste your actual Bokun secret key
```

Alternatively, you can use environment variables in Firebase Console:
- Go to Firebase Console > Functions > Configuration
- Add environment variables: `BOKUN_ACCESS_KEY` and `BOKUN_SECRET_KEY`

### 4. Deploy the Function

```bash
firebase deploy --only functions
```

This will deploy the `getBookings` Cloud Function.

### 4. Verify Deployment

After deployment, you should see output like:
```
✔  functions[getBookings(us-central1)] Successful create operation.
Function URL: https://us-central1-aurora-viking-staff.cloudfunctions.net/getBookings
```

## How It Works

1. **Web App**: When running on web (`kIsWeb`), the Flutter app calls the Cloud Function instead of Bokun directly
2. **Cloud Function**: Receives the date range, authenticates the user, and makes the Bokun API call server-side
3. **Response**: Returns the bookings data to the web app

## Mobile App

The mobile app continues to use direct Bokun API calls because:
- The `.env` file is not deployed with the mobile app
- API keys are only available at build time
- Mobile apps are more secure than web apps

## Troubleshooting

### Function Not Found Error

If you see "Function not found", make sure:
1. The function is deployed: `firebase deploy --only functions`
2. You're using the correct function name: `getBookings`
3. The Firebase project is correct

### Authentication Error

The Cloud Function requires authentication. Make sure users are logged in before calling it.

### API Key Not Configured

If you see "Bokun API keys not configured":
1. Set the config: `firebase functions:config:set bokun.api_key="..." bokun.secret="..."`
2. Redeploy: `firebase deploy --only functions`

### View Function Logs

```bash
firebase functions:log
```

## Updating Secrets

To update the Bokun API keys:

```bash
# Update secrets
firebase functions:secrets:set BOKUN_ACCESS_KEY
firebase functions:secrets:set BOKUN_SECRET_KEY
# Redeploy to apply changes
firebase deploy --only functions
```

## Security Notes

- ✅ API keys are stored securely in Firebase Functions config
- ✅ Keys are never exposed to the client
- ✅ Function requires user authentication
- ✅ All requests are logged (without sensitive data)

