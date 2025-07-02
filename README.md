# Aurora Viking Staff App

A comprehensive staff management application for Aurora Viking tour guides, built with Flutter.

## 🚀 Features

### **Staff Features**
- **Shift Management**: Apply for Day Tours and Northern Lights shifts with calendar interface
- **Photo Upload**: Upload tour photos with guide information and bus selection
- **Live Tracking**: Real-time location tracking for tour buses
- **Profile Management**: View and edit personal information and shift statistics

### **Admin Features**
- **Admin Dashboard**: Secure admin access with password authentication
- **Live Tracking Map**: Monitor all active tours and guide locations
- **Shift Management**: Review and approve pending shift applications
- **Guide Management**: View and manage all registered guides
- **Reports & Analytics**: Comprehensive reporting system

## 📱 Screenshots

*Screenshots will be added here*

## 🛠️ Tech Stack

- **Framework**: Flutter 3.8.1+
- **Language**: Dart
- **State Management**: Provider
- **Backend**: Firebase (planned)
- **Maps**: Google Maps/Leaflet (planned)
- **Storage**: Google Drive (planned)

## 📋 Prerequisites

- Flutter SDK 3.8.1 or higher
- Dart SDK
- Android Studio / VS Code
- Git

## 🔧 Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/aurora-viking-staff.git
   cd aurora-viking-staff
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the app**
   ```bash
   flutter run
   ```

## 🏗️ Project Structure

```
lib/
├── core/
│   ├── auth/           # Authentication services
│   ├── models/         # Data models
│   ├── services/       # API and storage services
│   ├── theme/          # App theme and colors
│   └── utils/          # Utility functions
├── modules/
│   ├── admin/          # Admin dashboard and features
│   ├── photos/         # Photo upload functionality
│   ├── profile/        # User profile management
│   ├── shifts/         # Shift management
│   └── tracking/       # Location tracking
├── screens/            # Main app screens
└── widgets/            # Reusable UI components
```

## 🔐 Admin Access

To access admin features:
1. Navigate to the **Dashboard** tab
2. Click **"Login to Admin Mode"**
3. Enter the admin password: `aurora2024`

## 🚧 Development Status

### ✅ Completed
- [x] Basic app structure and navigation
- [x] Admin authentication system
- [x] Profile management
- [x] Shift application interface
- [x] Photo upload interface
- [x] Tracking interface
- [x] Admin dashboard

### 🔄 In Progress
- [ ] Firebase integration
- [ ] Real-time location tracking
- [ ] Google Drive photo upload
- [ ] Push notifications

### 📋 Planned
- [ ] Advanced analytics
- [ ] Multi-language support
- [ ] Offline mode

## 🔧 Configuration

### Environment Setup
Create a `.env` file in the root directory:
```env
# Add your configuration variables here
```

### Firebase Setup (Future)
1. Create a Firebase project
2. Add `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
3. Configure Firebase Authentication and Firestore

## 📱 Platform Support

- ✅ Android
- ✅ iOS
- ✅ Web (planned)
- ✅ Desktop (planned)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👥 Team

- **Developer**: [Your Name]
- **Company**: Aurora Viking
- **Contact**: [your.email@auroraviking.com]

## 🆘 Support

For support and questions:
- Email: [support@auroraviking.com]
- Documentation: [Link to docs]
- Issues: [GitHub Issues](https://github.com/yourusername/aurora-viking-staff/issues)

---

**Aurora Viking Staff App** - Making tour management efficient and seamless! 🚌✨
