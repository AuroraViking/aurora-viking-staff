# Deploy Firestore Rules

## Method 1: Firebase Console (Recommended)

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Go to **Firestore Database** → **Rules**
4. Copy the contents of `firestore_rules.txt`
5. Paste into the rules editor
6. Click **Publish**

## Method 2: Firebase CLI

If you have Firebase CLI installed:

```bash
# Install Firebase CLI (if not already installed)
npm install -g firebase-tools

# Login to Firebase
firebase login

# Initialize Firebase (if not already done)
firebase init firestore

# Deploy rules
firebase deploy --only firestore:rules
```

## Method 3: Manual Copy

1. Open `firestore_rules.txt`
2. Copy all content
3. Go to Firebase Console → Firestore Database → Rules
4. Replace existing rules with copied content
5. Click **Publish**

## Important Notes

- The rules now include access to the `buses` collection
- All authenticated users can read/write bus data
- Location history has validation for required fields
- Bus locations and pickup data are accessible to authenticated users

## Testing

After deploying, test by:
1. Adding a new bus in the Bus Management screen
2. Checking if the bus appears in the list
3. Verifying that tracking works with the new bus

## Troubleshooting

If you still get permission errors:
1. Make sure you're logged in to the app
2. Check that the rules were published successfully
3. Wait a few minutes for rules to propagate
4. Try refreshing the app 