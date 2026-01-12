#!/bin/bash

# Build Flutter web for production with API keys from .env file
# Output goes to build/web/

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🏗️  Aurora Viking Staff - Web Build${NC}"
echo ""

# Check if .env exists
if [ ! -f ".env" ]; then
    echo -e "${RED}❌ .env file not found!${NC}"
    exit 1
fi

# Read GOOGLE_MAPS_API_KEY from .env
MAPS_KEY=$(grep -E "^GOOGLE_MAPS_API_KEY=" .env | cut -d '=' -f2 | tr -d '"' | tr -d "'" | tr -d ' ')

DART_DEFINES=""

if [ -n "$MAPS_KEY" ] && [ "$MAPS_KEY" != "your_google_maps_api_key_here" ]; then
    DART_DEFINES="--dart-define=GOOGLE_MAPS_API_KEY=$MAPS_KEY"
    echo -e "${GREEN}✅ Google Maps API key loaded${NC}"
else
    echo -e "${YELLOW}⚠️  Building without Maps API key${NC}"
fi

echo ""
echo -e "${GREEN}📦 Building for production...${NC}"
echo ""

# Clean first
flutter clean
flutter pub get

# Build
if [ -n "$DART_DEFINES" ]; then
    flutter build web --release $DART_DEFINES
else
    flutter build web --release
fi

echo ""
echo -e "${GREEN}✅ Build complete!${NC}"
echo -e "   Output: ${YELLOW}build/web/${NC}"
echo ""
echo "To deploy, upload the contents of build/web/ to your web server."


