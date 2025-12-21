#!/bin/bash
# Deploy script for Aurora Viking Staff web app to Firebase Hosting
# This script replaces the API key placeholder before building and deploying

set -e

echo "========================================"
echo "Aurora Viking Staff - Web Deployment"
echo "========================================"
echo ""

# Check if .env file exists
if [ ! -f .env ]; then
    echo "ERROR: .env file not found!"
    echo "Please create a .env file with GOOGLE_MAPS_API_KEY"
    exit 1
fi

echo "[1/4] Reading API key from .env..."
MAPS_KEY=$(grep GOOGLE_MAPS_API_KEY .env | cut -d '=' -f2)

if [ -z "$MAPS_KEY" ]; then
    echo "ERROR: GOOGLE_MAPS_API_KEY not found in .env file!"
    exit 1
fi

echo "[2/4] Replacing placeholder in web/index.html..."
sed -i.bak "s/MAPS_API_KEY_PLACEHOLDER/$MAPS_KEY/g" web/index.html

echo "[3/4] Building Flutter web app with API key..."
flutter build web --release --dart-define=GOOGLE_MAPS_API_KEY="$MAPS_KEY"

echo "[4/4] Deploying to Firebase Hosting..."
firebase deploy --only hosting

echo ""
echo "[5/5] Restoring placeholder in web/index.html..."
sed -i.bak "s/$MAPS_KEY/MAPS_API_KEY_PLACEHOLDER/g" web/index.html
rm -f web/index.html.bak

echo ""
echo "========================================"
echo "Deployment Complete!"
echo "========================================"
echo "Your app is live at: https://aurora-viking-staff.web.app"
echo ""

