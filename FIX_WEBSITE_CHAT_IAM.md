# Fix Website Chat IAM Permissions

⚠️ **Organization Policy Restriction Detected**

The functions are deployed but there's an organization policy preventing public access. You'll need to either:

1. **Request an exception** from your GCP organization admin
2. **Use the Firebase Console** (may have different permissions)
3. **Use API keys** instead of public access (alternative approach)

## Current Status

✅ Functions are deployed and working  
❌ Public IAM permissions blocked by org policy

## Option 1: Firebase Console (Try This First)

1. Go to https://console.firebase.google.com/project/aurora-viking-staff/functions
2. For each function (`createWebsiteSession`, `updateWebsiteSession`, `sendWebsiteMessage`, `updateWebsitePresence`):
   - Click on the function name
   - Go to "Permissions" tab  
   - Click "Add Principal"
   - Principal: `allUsers`
   - Role: `Cloud Functions Invoker`
   - Click "Save"

If this fails with a permission error, you'll need to contact your GCP organization admin.

## Option 2: Request Organization Policy Exception

Contact your GCP organization admin and request:
- Exception to allow public Cloud Functions invokers
- Or specific project-level exception for `aurora-viking-staff`

## Option 3: Alternative - Use API Keys (If Public Access Not Possible)

If public access isn't allowed, we can modify the widget to use API keys instead. This requires:
1. Creating API keys in GCP
2. Updating the widget to include API key in requests
3. Configuring Cloud Functions to validate API keys

Let me know if you want to implement this alternative approach.

## Option 1: Using gcloud CLI (Recommended)

```powershell
# Set public access for website chat functions
gcloud functions add-invoker-policy-binding createWebsiteSession --region=us-central1 --member="allUsers" --role="roles/cloudfunctions.invoker"
gcloud functions add-invoker-policy-binding updateWebsiteSession --region=us-central1 --member="allUsers" --role="roles/cloudfunctions.invoker"
gcloud functions add-invoker-policy-binding sendWebsiteMessage --region=us-central1 --member="allUsers" --role="roles/cloudfunctions.invoker"
gcloud functions add-invoker-policy-binding updateWebsitePresence --region=us-central1 --member="allUsers" --role="roles/cloudfunctions.invoker"
```

## Option 2: Using Firebase Console

1. Go to https://console.firebase.google.com/project/aurora-viking-staff/functions
2. For each function (`createWebsiteSession`, `updateWebsiteSession`, `sendWebsiteMessage`, `updateWebsitePresence`):
   - Click on the function name
   - Go to "Permissions" tab
   - Click "Add Principal"
   - Principal: `allUsers`
   - Role: `Cloud Functions Invoker`
   - Click "Save"

## Option 3: Using Cloud Console

1. Go to https://console.cloud.google.com/functions/list?project=aurora-viking-staff
2. For each function, click the three dots → "Edit"
3. Go to "Permissions" tab
4. Click "Add Principal"
5. New principals: `allUsers`
6. Role: `Cloud Functions Invoker`
7. Save

## Verify

After setting permissions, test the function:
```powershell
curl https://us-central1-aurora-viking-staff.cloudfunctions.net/createWebsiteSession -Method POST -ContentType "application/json" -Body '{"pageUrl":"https://test.com"}'
```

You should get a JSON response with `sessionId`, `conversationId`, and `customerId`.

---

**Note:** The functions are already deployed and working - they just need public access permissions to be callable from the website widget.

