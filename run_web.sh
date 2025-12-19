#!/bin/bash

# =============================================================================
# Aurora Viking Staff - Web Runner
# =============================================================================
# This script:
# 1. Reads API keys from .env
# 2. Injects them into web/index.html (temporarily)
# 3. Runs Flutter web
# 4. Restores the original index.html (so keys aren't committed)
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       🌌 Aurora Viking Staff - Web Runner 🌌              ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if .env exists
if [ ! -f ".env" ]; then
    echo -e "${RED}❌ .env file not found!${NC}"
    echo ""
    echo "Please create a .env file with your API keys:"
    echo ""
    echo "  GOOGLE_MAPS_API_KEY=your_maps_key_here"
    echo "  FIREBASE_WEB_API_KEY=your_firebase_key_here"
    echo ""
    echo "Get Firebase Web API key from:"
    echo "  Firebase Console > Project Settings > Your apps > Web app > apiKey"
    echo ""
    exit 1
fi

# Read API keys from .env
MAPS_KEY=$(grep -E "^GOOGLE_MAPS_API_KEY=" .env 2>/dev/null | cut -d '=' -f2 | tr -d '"' | tr -d "'" | tr -d ' ')
FIREBASE_KEY=$(grep -E "^FIREBASE_WEB_API_KEY=" .env 2>/dev/null | cut -d '=' -f2 | tr -d '"' | tr -d "'" | tr -d ' ')

echo -e "${CYAN}📋 Checking API keys...${NC}"
echo ""

KEYS_OK=true

# Check Firebase key (REQUIRED!)
if [ -z "$FIREBASE_KEY" ] || [ "$FIREBASE_KEY" = "your_firebase_web_api_key_here" ]; then
    echo -e "${RED}❌ FIREBASE_WEB_API_KEY not set!${NC}"
    echo -e "   ${YELLOW}Firebase won't work without this key.${NC}"
    echo -e "   Get it from: Firebase Console > Project Settings > Web app"
    echo ""
    KEYS_OK=false
else
    echo -e "${GREEN}✅ Firebase Web API key: ****${FIREBASE_KEY: -4}${NC}"
fi

# Check Maps key (optional but recommended)
if [ -z "$MAPS_KEY" ] || [ "$MAPS_KEY" = "your_google_maps_api_key_here" ]; then
    echo -e "${YELLOW}⚠️  GOOGLE_MAPS_API_KEY not set${NC}"
    echo -e "   Maps features won't work."
    MAPS_KEY=""
else
    echo -e "${GREEN}✅ Google Maps API key: ****${MAPS_KEY: -4}${NC}"
fi

echo ""

# Warn if Firebase key is missing
if [ "$KEYS_OK" = false ]; then
    echo -e "${RED}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}  FIREBASE_WEB_API_KEY is required for web to work!${NC}"
    echo -e "${RED}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Add this to your .env file:"
    echo ""
    echo "  FIREBASE_WEB_API_KEY=AIzaSy..."
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Backup original index.html
echo -e "${CYAN}🔧 Preparing web/index.html...${NC}"

if [ -f "web/index.html" ]; then
    cp web/index.html web/index.html.original
fi

# Inject Firebase API key
if [ -n "$FIREBASE_KEY" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/FIREBASE_API_KEY_PLACEHOLDER/$FIREBASE_KEY/g" web/index.html
    else
        sed -i "s/FIREBASE_API_KEY_PLACEHOLDER/$FIREBASE_KEY/g" web/index.html
    fi
    echo -e "${GREEN}   ✓ Firebase key injected${NC}"
fi

# Inject Maps API key
if [ -n "$MAPS_KEY" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/MAPS_API_KEY_PLACEHOLDER/$MAPS_KEY/g" web/index.html
    else
        sed -i "s/MAPS_API_KEY_PLACEHOLDER/$MAPS_KEY/g" web/index.html
    fi
    echo -e "${GREEN}   ✓ Maps key injected${NC}"
else
    # Remove the Maps script tag entirely if no key
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' '/MAPS_API_KEY_PLACEHOLDER/d' web/index.html
    else
        sed -i '/MAPS_API_KEY_PLACEHOLDER/d' web/index.html
    fi
    echo -e "${YELLOW}   ✓ Maps script removed (no key)${NC}"
fi

echo ""
echo -e "${CYAN}🌐 Starting Flutter Web on Chrome...${NC}"
echo -e "${CYAN}   Press 'q' to quit, 'r' to hot reload${NC}"
echo ""

# Build dart-define arguments (for Dart code access to keys)
DART_DEFINES=""
if [ -n "$MAPS_KEY" ]; then
    DART_DEFINES="$DART_DEFINES --dart-define=GOOGLE_MAPS_API_KEY=$MAPS_KEY"
fi

# Function to restore original file
cleanup() {
    echo ""
    echo -e "${CYAN}🧹 Cleaning up...${NC}"
    if [ -f "web/index.html.original" ]; then
        mv web/index.html.original web/index.html
        echo -e "${GREEN}   ✓ Restored original index.html${NC}"
    fi
}

# Set trap to restore file on exit
trap cleanup EXIT

# Run Flutter
flutter run -d chrome $DART_DEFINES "$@"
