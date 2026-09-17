#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

usage() {
  cat >&2 <<'EOF'
Usage: ./scripts/build-release.sh --macos-provisioning-profile PATH

The profile may also be supplied through PING_MACOS_PROVISIONING_PROFILE.
EOF
}

MACOS_PROVISIONING_PROFILE="${PING_MACOS_PROVISIONING_PROFILE:-}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --macos-provisioning-profile|--provisioning-profile)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then
        echo "A path is required for $1." >&2
        usage
        exit 2
      fi
      MACOS_PROVISIONING_PROFILE="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [ -z "$MACOS_PROVISIONING_PROFILE" ]; then
  echo "A macOS provisioning profile is required for APNs release builds." >&2
  echo "Pass --macos-provisioning-profile PATH or set PING_MACOS_PROVISIONING_PROFILE." >&2
  exit 1
fi

if [ ! -f "$MACOS_PROVISIONING_PROFILE" ] || [ ! -r "$MACOS_PROVISIONING_PROFILE" ]; then
  echo "macOS provisioning profile is missing or unreadable: $MACOS_PROVISIONING_PROFILE" >&2
  exit 1
fi

PROFILE_PLIST="$(mktemp -t ping-provisioning-profile)"
TMP_ENTITLEMENTS=""
cleanup() {
  rm -f "$PROFILE_PLIST"
  if [ -n "$TMP_ENTITLEMENTS" ]; then
    rm -f "$TMP_ENTITLEMENTS"
  fi
}
trap cleanup EXIT

if ! security cms -D -i "$MACOS_PROVISIONING_PROFILE" -o "$PROFILE_PLIST" >/dev/null 2>&1; then
  echo "The macOS provisioning profile is not a valid signed profile: $MACOS_PROVISIONING_PROFILE" >&2
  exit 1
fi

PROFILE_APPLICATION_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$PROFILE_PLIST" 2>/dev/null || true)"
if [ "$PROFILE_APPLICATION_IDENTIFIER" != "878FAHTFQJ.com.youngminpark.ping.Ping" ]; then
  echo "The macOS provisioning profile is not for the Ping application." >&2
  exit 1
fi

PROFILE_TEAM_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' "$PROFILE_PLIST" 2>/dev/null || true)"
if [ "$PROFILE_TEAM_IDENTIFIER" != "878FAHTFQJ" ]; then
  echo "The macOS provisioning profile belongs to an unexpected team." >&2
  exit 1
fi

PROFILE_PLATFORM="$(/usr/libexec/PlistBuddy -c 'Print :Platform:0' "$PROFILE_PLIST" 2>/dev/null || true)"
if [ "$PROFILE_PLATFORM" != "OSX" ]; then
  echo "The provisioning profile must target macOS (OSX)." >&2
  exit 1
fi

PROFILE_EXPIRATION="$(/usr/bin/plutil -extract ExpirationDate raw -o - "$PROFILE_PLIST" 2>/dev/null || true)"
PROFILE_EXPIRATION_EPOCH="$(/bin/date -j -f "%Y-%m-%dT%H:%M:%SZ" "$PROFILE_EXPIRATION" "+%s" 2>/dev/null || true)"
if [ -z "$PROFILE_EXPIRATION_EPOCH" ] || [ "$PROFILE_EXPIRATION_EPOCH" -le "$(/bin/date +%s)" ]; then
  echo "The macOS provisioning profile is missing or expired." >&2
  exit 1
fi

PROFILE_APNS_ENV="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.aps-environment' "$PROFILE_PLIST" 2>/dev/null || true)"
if [ "$PROFILE_APNS_ENV" != "production" ]; then
  echo "The macOS provisioning profile must grant com.apple.developer.aps-environment=production." >&2
  exit 1
fi

if [ ! -f "Resources/Supabase.plist" ]; then
  echo "Supabase.plist is required at Resources/Supabase.plist for release builds." >&2
  exit 1
fi

# Real releases must be built from main so the published binary matches the
# released source. A past release shipped a DMG built from a stale feature
# branch — the feature was in the committed source but missing from the app.
# Verification-only builds (PING_VERIFY_ONLY) may run from any branch.
if [ -z "${PING_VERIFY_ONLY:-}" ]; then
  CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  if [ "$CURRENT_BRANCH" != "main" ]; then
    echo "Release builds must run on 'main' (currently: $CURRENT_BRANCH)." >&2
    echo "Merge your feature branches into main and build from there, or set" >&2
    echo "PING_VERIFY_ONLY=1 for a signing/notarization smoke test." >&2
    exit 1
  fi
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
  clean build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO

APP="build/Build/Products/Release/Ping.app"
EMBEDDED_PROFILE="$APP/Contents/embedded.provisionprofile"

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
if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
  echo "Required Sparkle.framework missing: $SPARKLE_FRAMEWORK" >&2
  exit 1
fi

sign_preserving_metadata "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate"
sign_preserving_metadata "$SPARKLE_FRAMEWORK/Versions/B/Updater.app"
sign_preserving_metadata "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
sign_preserving_metadata "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
sign_framework "$SPARKLE_FRAMEWORK"

# The APNs profile must be present before the outer signature is created. Keep
# the profile supplied by the release operator; never download or generate one.
cp "$MACOS_PROVISIONING_PROFILE" "$EMBEDDED_PROFILE"
if [ ! -f "$EMBEDDED_PROFILE" ]; then
  echo "Failed to embed the macOS provisioning profile in the app bundle." >&2
  exit 1
fi

# Sign the app last (outermost). The Developer ID designated requirement is
# anchored to the team + bundle id and is stable across builds, so TCC grants
# survive updates without the old ad-hoc requirement pin.
codesign --force --sign "$SIGN_IDENTITY" \
  --options runtime --timestamp \
  --entitlements Ping.entitlements \
  "$APP"

TMP_ENTITLEMENTS="$(mktemp -t ping-final-entitlements)"
if ! codesign -d --entitlements :- "$APP" > "$TMP_ENTITLEMENTS"; then
  echo "Unable to inspect the final signed app entitlements." >&2
  exit 1
fi

FINAL_APNS_ENV="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.aps-environment' "$TMP_ENTITLEMENTS" 2>/dev/null || true)"
if [ "$FINAL_APNS_ENV" != "production" ]; then
  echo "The final signed app must contain com.apple.developer.aps-environment=production." >&2
  exit 1
fi

if [ ! -f "$EMBEDDED_PROFILE" ]; then
  echo "The signed app is missing Contents/embedded.provisionprofile." >&2
  exit 1
fi

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

# Keep the website's macOS download in lockstep with this build so the landing
# page never advertises or serves a stale DMG. ReleaseVersionContractTests
# enforces this agreement; stamping it here is what keeps releases from
# half-shipping (appcast bumped, website left behind).
ROUTES="web/src/routes.tsx"
if [ -f "$ROUTES" ]; then
  sed -i '' \
    -e "s|MAC_APP_VERSION = \"v[0-9][0-9.]*\";|MAC_APP_VERSION = \"v$VERSION\";|" \
    -e "s|MAC_DOWNLOAD_URL = \"/downloads/Ping-v[0-9][0-9.]*\.dmg\";|MAC_DOWNLOAD_URL = \"/downloads/Ping-v$VERSION.dmg\";|" \
    "$ROUTES"
  if ! grep -qF "MAC_APP_VERSION = \"v$VERSION\";" "$ROUTES" \
     || ! grep -qF "MAC_DOWNLOAD_URL = \"/downloads/Ping-v$VERSION.dmg\";" "$ROUTES"; then
    echo "Failed to stamp $ROUTES with v$VERSION (format may have drifted)." >&2
    exit 1
  fi
  echo "Stamped $ROUTES -> v$VERSION"
fi

# Same lockstep for the README install instruction so its DMG reference never
# lags behind the shipped build (release notes above it stay hand-written).
README="README.md"
if [ -f "$README" ]; then
  sed -i '' -e "s|Ping-v[0-9][0-9.]*\.dmg|Ping-v$VERSION.dmg|g" "$README"
  if ! grep -qF "Ping-v$VERSION.dmg" "$README"; then
    echo "Failed to stamp $README with v$VERSION (format may have drifted)." >&2
    exit 1
  fi
  echo "Stamped $README -> v$VERSION"
fi

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
  --download-url-prefix "https://0minping.vercel.app/downloads/" \
  --link "https://0minping.vercel.app" \
  --maximum-versions 10 \
  web/public/downloads

if [ -f "web/public/downloads/appcast.xml" ]; then
  mv "web/public/downloads/appcast.xml" "web/public/appcast.xml"
  echo "Wrote web/public/appcast.xml"
else
  echo "generate_appcast did not produce appcast.xml" >&2
  exit 1
fi
