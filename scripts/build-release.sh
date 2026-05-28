#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f "Resources/Supabase.plist" ]; then
  echo "Supabase.plist is required at Resources/Supabase.plist for release builds." >&2
  exit 1
fi

# --- Developer ID signing & notarization configuration ---
# Override either of these via environment if your setup differs.
#
# SIGN_IDENTITY: the Developer ID Application certificate in the login keychain.
#   codesign matches by substring, so the short form "Developer ID Application"
#   also works when exactly one such certificate is installed.
SIGN_IDENTITY="${PING_SIGN_IDENTITY:-Developer ID Application: Youngmin Park (878FAHTFQJ)}"
# NOTARY_PROFILE: a notarytool keychain profile created once from an App Store
#   Connect API key (recommended — runs headlessly, no Apple ID 2FA prompts):
#     xcrun notarytool store-credentials "ping-notary" \
#       --key AuthKey_XXXXXXXXXX.p8 --key-id <KEY_ID> --issuer <ISSUER_ID>
NOTARY_PROFILE="${PING_NOTARY_PROFILE:-ping-notary}"

if ! security find-identity -v -p codesigning | grep -qF "$SIGN_IDENTITY"; then
  echo "Signing identity not found in the login keychain: $SIGN_IDENTITY" >&2
  echo "Install it via Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application," >&2
  echo "or set PING_SIGN_IDENTITY to match 'security find-identity -v -p codesigning'." >&2
  exit 1
fi

# Confirm the profile resolves and the API key is still valid (quick API call).
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "notarytool keychain profile '$NOTARY_PROFILE' is missing or invalid." >&2
  echo "Create it once with your App Store Connect API key:" >&2
  echo "  xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --key AuthKey_XXXXXXXXXX.p8 --key-id <KEY_ID> --issuer <ISSUER_ID>" >&2
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

sign_preserving_metadata() {
  local code_object="$1"
  if [ ! -e "$code_object" ]; then
    echo "Expected Sparkle code object missing: $code_object" >&2
    exit 1
  fi

  # Preserve Sparkle's own entitlements, but let codesign derive a fresh
  # designated requirement from the Developer ID cert (notarization rejects the
  # ad-hoc requirement). --timestamp adds the secure timestamp notarization needs.
  codesign --force --sign "$SIGN_IDENTITY" \
    --options runtime --timestamp \
    --preserve-metadata=entitlements \
    "$code_object"
}

sign_framework() {
  local code_object="$1"
  if [ ! -e "$code_object" ]; then
    echo "Expected Sparkle framework missing: $code_object" >&2
    exit 1
  fi

  codesign --force --sign "$SIGN_IDENTITY" \
    --options runtime --timestamp \
    --preserve-metadata=entitlements \
    "$code_object"
}

SPARKLE_FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE_FRAMEWORK" ]; then
  sign_preserving_metadata "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate"
  sign_preserving_metadata "$SPARKLE_FRAMEWORK/Versions/B/Updater.app"
  sign_preserving_metadata "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
  sign_preserving_metadata "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
  sign_framework "$SPARKLE_FRAMEWORK"
fi

# Sign the app last (outermost). The Developer ID designated requirement is
# anchored to the team + bundle id and is stable across builds, so TCC grants
# survive updates without the old ad-hoc requirement pin.
codesign --force --sign "$SIGN_IDENTITY" \
  --options runtime --timestamp \
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

# Notarize the DMG (Apple checks the signed app inside), then staple the ticket
# so Gatekeeper clears it offline on first launch. Must happen before the copy
# below so the DMG served to users — and fed to Sparkle's appcast — is stapled.
echo "Notarizing dist/Ping-v$VERSION.dmg (this can take a few minutes)..."
xcrun notarytool submit "dist/Ping-v$VERSION.dmg" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

xcrun stapler staple "dist/Ping-v$VERSION.dmg"
xcrun stapler validate "dist/Ping-v$VERSION.dmg"

# Verification builds stop here: prove signing + notarization end to end without
# touching the published download or the tracked appcast. Set PING_VERIFY_ONLY=1.
if [ -n "${PING_VERIFY_ONLY:-}" ]; then
  echo "PING_VERIFY_ONLY set — skipping web copy + appcast generation."
  # Authoritative check: mount the DMG and assess the app exactly as Gatekeeper
  # would on first launch. Expect "accepted / source=Notarized Developer ID".
  # (Don't spctl the DMG itself — it carries a stapled ticket, not a code
  # signature, so a primary-signature assessment would wrongly report "rejected".)
  VERIFY_MNT="$(mktemp -d)"
  hdiutil attach "dist/Ping-v$VERSION.dmg" -nobrowse -quiet -mountpoint "$VERIFY_MNT"
  if spctl --assess --type exec -vv "$VERIFY_MNT/Ping.app"; then
    GK_OK=1
  else
    GK_OK=0
  fi
  hdiutil detach "$VERIFY_MNT" -quiet || true
  rmdir "$VERIFY_MNT" 2>/dev/null || true
  if [ "$GK_OK" != 1 ]; then
    echo "Gatekeeper rejected the app — notarization/signing is not valid." >&2
    exit 1
  fi
  echo "Verification OK: dist/Ping-v$VERSION.dmg is signed, notarized, and stapled."
  exit 0
fi

mkdir -p web/public/downloads
cp "dist/Ping-v$VERSION.dmg" "web/public/downloads/Ping-v$VERSION.dmg"

echo "Built (signed + notarized + stapled) dist/Ping-v$VERSION.dmg"
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
