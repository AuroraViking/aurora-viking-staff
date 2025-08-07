# Firebase Setup Guide for Aurora Viking Staff

## 🔥 Firebase Configuration Required

To enable authentication and data persistence for the Aurora Viking Staff app, you need to set up Firebase.

### 1. Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click "Create a project" or "Add project"
3. Enter project name: `aurora-viking-staff`
4. Enable Google Analytics (optional)
5. Click "Create project"

### 2. Enable Authentication

1. In Firebase Console, go to "Authentication" → "Sign-in method"
2. Enable "Email/Password" authentication
3. Click "Save"

### 3. Create Firestore Database

1. Go to "Firestore Database" → "Create database"
2. Choose "Start in test mode" (for development)
3. Select a location close to your users
4. Click "Done"

### 4. Add Users (Optional)

1. Go to "Authentication" → "Users"
2. Click "Add user"
3. Enter email and password for guides/admins
4. Repeat for all team members

### 5. Security Rules (Recommended)

In Firestore Database → Rules, use these rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can read/write their own data
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Booking status - authenticated users can read/write
    match /booking_status/{document} {
      allow read, write: if request.auth != null;
    }
    
    // Pickup assignments - authenticated users can read/write
    match /pickup_assignments/{document} {
      allow read, write: if request.auth != null;
    }
  }
}
```

### 6. Test Login

1. Run the app
2. Use the email/password you created in step 4
3. You should be able to log in and access the app

## 📱 Features Enabled

With Firebase configured, the app now supports:

- ✅ **User Authentication** - Secure login for guides and admins
- ✅ **Persistent Data** - Booking statuses (arrived/no-show) saved to cloud
- ✅ **Real-time Updates** - Status changes sync across devices
- ✅ **User Management** - Different roles for guides and admins
- ✅ **Secure Storage** - All data stored in Firebase Firestore

## 🔧 Troubleshooting

If you encounter issues:

1. **Firebase not initialized**: Check console logs for initialization errors
2. **Authentication fails**: Verify email/password in Firebase Console
3. **Database errors**: Check Firestore rules and permissions
4. **Network issues**: Ensure internet connection is stable

## 📞 Support

For Firebase-specific issues, refer to the [Firebase Documentation](https://firebase.google.com/docs). 