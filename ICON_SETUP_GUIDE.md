# 🛡️ Ægishjálmur App Icon Setup Guide

## 🎯 **What We're Adding**
The **Ægishjálmur (Helm of Awe)** - an authentic Norse magical symbol representing protection and power. Perfect for Aurora Viking Staff!

## 📱 **Icon Requirements**

### **Android Icons Needed:**
- `mipmap-mdpi/ic_launcher.png` - 48x48 px
- `mipmap-hdpi/ic_launcher.png` - 72x72 px  
- `mipmap-xhdpi/ic_launcher.png` - 96x96 px
- `mipmap-xxhdpi/ic_launcher.png` - 144x144 px
- `mipmap-xxxhdpi/ic_launcher.png` - 192x192 px

### **iOS Icons Needed:**
- `AppIcon.appiconset/Icon-App-20x20@1x.png` - 20x20 px
- `AppIcon.appiconset/Icon-App-20x20@2x.png` - 40x40 px
- `AppIcon.appiconset/Icon-App-20x20@3x.png` - 60x60 px
- `AppIcon.appiconset/Icon-App-29x29@1x.png` - 29x29 px
- `AppIcon.appiconset/Icon-App-29x29@2x.png` - 58x58 px
- `AppIcon.appiconset/Icon-App-29x29@3x.png` - 87x87 px
- `AppIcon.appiconset/Icon-App-40x40@1x.png` - 40x40 px
- `AppIcon.appiconset/Icon-App-40x40@2x.png` - 80x80 px
- `AppIcon.appiconset/Icon-App-40x40@3x.png` - 120x120 px
- `AppIcon.appiconset/Icon-App-60x60@2x.png` - 120x120 px
- `AppIcon.appiconset/Icon-App-60x60@3x.png` - 180x180 px
- `AppIcon.appiconset/Icon-App-76x76@1x.png` - 76x76 px
- `AppIcon.appiconset/Icon-App-76x76@2x.png` - 152x152 px
- `AppIcon.appiconset/Icon-App-83.5x83.5@2x.png` - 167x167 px
- `AppIcon.appiconset/Icon-App-1024x1024@1x.png` - 1024x1024 px

## 🛠️ **How to Generate Icons**

### **Option 1: Online Icon Generators (Recommended)**
1. **Go to [App Icon Generator](https://appicon.co/)**
2. **Upload the `assets/icon_dark.svg` file**
3. **Download the generated icon pack**
4. **Replace the existing icons in your project**

### **Option 2: Use Flutter's Icon Generator**
1. **Install `flutter_launcher_icons` package:**
   ```yaml
   dev_dependencies:
     flutter_launcher_icons: ^0.13.1
   ```

2. **Add configuration to `pubspec.yaml`:**
   ```yaml
   flutter_launcher_icons:
     android: "launcher_icon"
     ios: true
     image_path: "assets/icon_dark.png"
     min_sdk_android: 21
     web:
       generate: true
       image_path: "assets/icon_dark.png"
       background_color: "#0A0D12"
       theme_color: "#00E5FF"
   ```

3. **Run the generator:**
   ```bash
   flutter pub get
   flutter pub run flutter_launcher_icons:main
   ```

### **Option 3: Manual Conversion**
1. **Use Inkscape, GIMP, or Photoshop**
2. **Open `assets/icon_dark.svg`**
3. **Export to PNG at each required size**
4. **Replace existing icons manually**

## 🎨 **Icon Design Details**

### **Colors Used:**
- **Background**: `#0A0D12` (Dark slate - matches your app theme)
- **Symbol**: `#00E5FF` (Primary teal - your app's accent color)
- **Stroke Width**: 2px for visibility at small sizes

### **Symbol Meaning:**
- **Ægishjálmur** = "Helm of Awe" in Old Norse
- **8 arms** = Protection in all directions
- **Algiz runes** = Divine protection and connection to the gods
- **Central circle** = Unity and wholeness

## 📁 **File Locations to Replace**

### **Android:**
```
android/app/src/main/res/
├── mipmap-mdpi/ic_launcher.png
├── mipmap-hdpi/ic_launcher.png
├── mipmap-xhdpi/ic_launcher.png
├── mipmap-xxhdpi/ic_launcher.png
└── mipmap-xxxhdpi/ic_launcher.png
```

### **iOS:**
```
ios/Runner/Assets.xcassets/AppIcon.appiconset/
├── Icon-App-20x20@1x.png
├── Icon-App-20x20@2x.png
├── Icon-App-20x20@3x.png
├── Icon-App-29x29@1x.png
├── Icon-App-29x29@2x.png
├── Icon-App-29x29@3x.png
├── Icon-App-40x40@1x.png
├── Icon-App-40x40@2x.png
├── Icon-App-40x40@3x.png
├── Icon-App-60x60@2x.png
├── Icon-App-60x60@3x.png
├── Icon-App-76x76@1x.png
├── Icon-App-76x76@2x.png
├── Icon-App-83.5x83.5@2x.png
└── Icon-App-1024x1024@1x.png
```

## 🚀 **Quick Start (Recommended)**

1. **Go to [App Icon Generator](https://appicon.co/)**
2. **Upload `assets/icon_dark.svg`**
3. **Download the generated pack**
4. **Replace the icons in your project**
5. **Rebuild your app**

## ✨ **Result**
Your app will have a beautiful, authentic Norse magical symbol as its icon - perfect for Aurora Viking Staff! The Ægishjálmur represents protection, power, and connection to Norse heritage.

---

*"The Helm of Awe I wore before the sons of men, in defense of my treasure; amongst all, I alone was strong, I thought to myself, for I found no power a match for my own."* - Fáfnismál 