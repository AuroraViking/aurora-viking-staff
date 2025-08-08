# Deploy Updated Firestore Rules

The current Firestore rules are missing permissions for the `reordered_bookings` collection, which is causing the permission denied error when guides try to save their reordered pickup lists.

## Updated Rules

The rules in `firestore_rules.txt` have been updated to include:

```javascript
// Reordered bookings - guides can read/write their own reordered lists
match /reordered_bookings/{document} {
  allow read, write: if request.auth != null;
}
```

## How to Deploy

### Option 1: Firebase Console (Recommended)
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your Aurora Viking Staff project
3. Navigate to **Firestore Database** > **Rules**
4. Copy the contents of `firestore_rules.txt`
5. Paste into the rules editor
6. Click **Publish**

### Option 2: Firebase CLI
If you have Firebase CLI installed:

```bash
# Navigate to your project directory
cd aurora_viking_staff

# Deploy the rules
firebase deploy --only firestore:rules
```

### Option 3: Copy from firestore_rules.txt
Copy the entire contents of `firestore_rules.txt` and paste them into the Firebase Console rules editor.

## What This Fixes

After deploying these rules, guides will be able to:
- ✅ Save their custom pickup order
- ✅ Load their saved order when returning to the app
- ✅ Reset back to alphabetical order
- ✅ Have their preferences persist across app sessions

## Testing

After deploying the rules, test the drag-and-drop functionality:
1. Drag a pickup card to reorder it
2. Close and reopen the app
3. Verify the custom order is preserved
4. Test the reset button to return to alphabetical order 