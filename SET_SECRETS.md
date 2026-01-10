# Setting Firebase Function Secrets

## Step 1: Set Bokun Access Key

Run this command and paste your actual Bokun access key when prompted:

```bash
firebase functions:secrets:set BOKUN_ACCESS_KEY
```

When prompted, paste your actual Bokun access key from your `.env` file.

## Step 2: Set Bokun Secret Key

Run this command and paste your actual Bokun secret key when prompted:

```bash
firebase functions:secrets:set BOKUN_SECRET_KEY
```

When prompted, paste your actual Bokun secret key from your `.env` file.

## Step 3: Deploy

After setting both secrets, deploy:

```bash
firebase deploy --only functions
```

## Note

The secrets you set will be automatically available as environment variables (`process.env.BOKUN_ACCESS_KEY` and `process.env.BOKUN_SECRET_KEY`) in your Cloud Function.

