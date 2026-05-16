#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

xcodegen generate

xcodebuild \
  -project Ping.xcodeproj \
  -scheme Ping \
  -configuration Release \
  -derivedDataPath build \
  clean build

APP="build/Build/Products/Release/Ping.app"

codesign --force --deep --sign - \
  --options runtime \
  --entitlements Ping.entitlements \
  "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")

mkdir -p dist
rm -f "dist/Ping-v$VERSION.dmg"

create-dmg \
  --volname "Ping Installer" \
  --window-size 500 300 \
  --icon-size 100 \
  --icon "Ping.app" 125 150 \
  --app-drop-link 375 150 \
  "dist/Ping-v$VERSION.dmg" \
  "$APP"

echo "Built dist/Ping-v$VERSION.dmg"
