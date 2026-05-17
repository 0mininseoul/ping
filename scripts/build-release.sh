#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift scripts/generate-icons.swift
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

echo "Built dist/Ping-v$VERSION.dmg"
