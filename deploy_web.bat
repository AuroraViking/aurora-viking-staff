@echo off
REM Deploy script for Aurora Viking Staff web app to Firebase Hosting
REM This script replaces the API key placeholder before building and deploying

echo ========================================
echo Aurora Viking Staff - Web Deployment
echo ========================================
echo.

REM Check if .env file exists
if not exist .env (
    echo ERROR: .env file not found!
    echo Please create a .env file with GOOGLE_MAPS_API_KEY
    pause
    exit /b 1
)

echo [1/4] Reading API key from .env...
for /f "tokens=2 delims==" %%a in ('findstr /C:"GOOGLE_MAPS_API_KEY" .env') do set MAPS_KEY=%%a

if "%MAPS_KEY%"=="" (
    echo ERROR: GOOGLE_MAPS_API_KEY not found in .env file!
    pause
    exit /b 1
)

echo [2/4] Replacing placeholder in web/index.html...
powershell -Command "(Get-Content web\index.html) -replace 'MAPS_API_KEY_PLACEHOLDER', '%MAPS_KEY%' | Set-Content web\index.html"

echo [3/4] Building Flutter web app with API key...
call flutter build web --release --dart-define=GOOGLE_MAPS_API_KEY=%MAPS_KEY%
if errorlevel 1 (
    echo ERROR: Build failed!
    pause
    exit /b 1
)

echo [4/4] Deploying to Firebase Hosting...
call firebase deploy --only hosting
if errorlevel 1 (
    echo ERROR: Deployment failed!
    pause
    exit /b 1
)

echo.
echo [5/5] Restoring placeholder in web/index.html...
powershell -Command "(Get-Content web\index.html) -replace '%MAPS_KEY%', 'MAPS_API_KEY_PLACEHOLDER' | Set-Content web\index.html"

echo.
echo ========================================
echo Deployment Complete!
echo ========================================
echo Your app is live at: https://aurora-viking-staff.web.app
echo.
pause

