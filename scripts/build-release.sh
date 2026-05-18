#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f "Resources/Supabase.plist" ]; then
  echo "Supabase.plist is required at Resources/Supabase.plist for release builds." >&2
  exit 1
fi

swift scripts/generate-icons.swift
xcodegen generate

xcodebuild \
  -project Ping.xcodeproj \
  -scheme Ping \
  -configuration Release \
  -derivedDataPath build \
  clean build

APP="build/Build/Products/Release/Ping.app"

if [ ! -f "$APP/Contents/Resources/Supabase.plist" ]; then
  echo "Supabase.plist is required in the built app bundle." >&2
  exit 1
fi

codesign --force --deep --sign - \
  --options runtime \
  --entitlements Ping.entitlements \
  "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")

mkdir -p dist
DMG_ROOT="dist/dmg-root"

rm -rf "$DMG_ROOT" "dist/Ping-v$VERSION.dmg"
mkdir -p "$DMG_ROOT"

ditto "$APP" "$DMG_ROOT/Ping.app"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
  -volname "Ping Installer" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "dist/Ping-v$VERSION.dmg"

mkdir -p web/public/downloads
cp "dist/Ping-v$VERSION.dmg" "web/public/downloads/Ping-v$VERSION.dmg"

echo "Built dist/Ping-v$VERSION.dmg"
echo "Copied web/public/downloads/Ping-v$VERSION.dmg"

# Sparkle: sign the DMG with EdDSA and regenerate the appcast served at /appcast.xml.
# Requires generate_keys to have been run once (see scripts/sparkle-generate-keys.sh).
# shellcheck disable=SC1091
source scripts/sparkle-tools-path.sh

GENERATE_APPCAST="$SPARKLE_BIN/generate_appcast"
if [ ! -x "$GENERATE_APPCAST" ]; then
  echo "generate_appcast not found at $GENERATE_APPCAST" >&2
  exit 1
fi

"$GENERATE_APPCAST" \
  --account "com.youngminpark.ping.Ping" \
  --download-url-prefix "https://ping0min.vercel.app/downloads/" \
  --link "https://ping0min.vercel.app" \
  --maximum-versions 10 \
  web/public/downloads

if [ -f "web/public/downloads/appcast.xml" ]; then
  mv "web/public/downloads/appcast.xml" "web/public/appcast.xml"
  echo "Wrote web/public/appcast.xml"
else
  echo "generate_appcast did not produce appcast.xml" >&2
  exit 1
fi
