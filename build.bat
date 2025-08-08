@echo off
echo 🔧 Aurora Viking Staff - Build Script
echo =====================================

echo.
echo 📝 Injecting environment variables...
dart scripts/build_with_env.dart

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ❌ Environment injection failed!
    echo Please check your .env file and try again.
    pause
    exit /b 1
)

echo.
echo 🧹 Cleaning Flutter project...
flutter clean

echo.
echo 📦 Getting dependencies...
flutter pub get

echo.
echo 🚀 Starting the app...
flutter run

pause 