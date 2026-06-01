#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SCHEME="${SCHEME:-PingMobile}"
CONFIGURATION="${CONFIGURATION:-Release}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT/build/${SCHEME}-TestFlight.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$ROOT/build/${SCHEME}-AppStore}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-$ROOT/scripts/ExportOptions-AppStore.plist}"

ASC_API_KEY_ID="${ASC_API_KEY_ID:-TMC3PCHDCF}"
ASC_API_ISSUER_ID="${ASC_API_ISSUER_ID:-0d693e18-2317-4107-8b26-26afd98e64ae}"
ASC_API_PRIVATE_KEY_PATH="${ASC_API_PRIVATE_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_API_KEY_ID}.p8}"

BUMP_BUILD=0
BUILD_NUMBER="${BUILD_NUMBER:-}"
MARKETING_VERSION="${MARKETING_VERSION:-}"
IPA_PATH=""

usage() {
  cat <<EOF
Usage: scripts/upload-testflight.sh [options]

Builds, exports, and uploads PingMobile to TestFlight.

Options:
  --bump-build                 Increment the iOS-family build number in project.yml.
  --build-number <number>      Set PingMobile/PingPushService/PingWatch build number.
  --marketing-version <value>  Set PingMobile/PingPushService/PingWatch marketing version.
  --ipa <path>                 Upload an existing IPA instead of archiving/exporting.
  -h, --help                   Show this help.

Environment overrides:
  ASC_API_KEY_ID, ASC_API_ISSUER_ID, ASC_API_PRIVATE_KEY_PATH
  SCHEME, CONFIGURATION, ARCHIVE_PATH, EXPORT_PATH, EXPORT_OPTIONS_PLIST
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bump-build)
      BUMP_BUILD=1
      shift
      ;;
    --build-number)
      BUILD_NUMBER="${2:?missing build number}"
      shift 2
      ;;
    --marketing-version)
      MARKETING_VERSION="${2:?missing marketing version}"
      shift 2
      ;;
    --ipa)
      IPA_PATH="${2:?missing IPA path}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_file() {
  local path="$1"
  local label="$2"
  if [[ ! -f "$path" ]]; then
    echo "Missing $label: $path" >&2
    exit 1
  fi
}

update_versions_if_needed() {
  if [[ "$BUMP_BUILD" != "1" && -z "$BUILD_NUMBER" && -z "$MARKETING_VERSION" ]]; then
    return
  fi

  ruby - "$ROOT/project.yml" "$BUMP_BUILD" "$BUILD_NUMBER" "$MARKETING_VERSION" <<'RUBY'
path, bump_build, build_number, marketing_version = ARGV
targets = %w[PingMobile PingPushService PingWatch]
lines = File.readlines(path)

current_target = nil
build_numbers = {}

lines.each do |line|
  current_target = Regexp.last_match(1) if line =~ /^  ([A-Za-z0-9_]+):\s*$/
  next unless targets.include?(current_target)

  if line =~ /^        CURRENT_PROJECT_VERSION:\s*"([^"]+)"/
    build_numbers[current_target] = Regexp.last_match(1)
  end
end

missing = targets.reject { |target| build_numbers.key?(target) }
raise "Missing CURRENT_PROJECT_VERSION for #{missing.join(", ")}" unless missing.empty?

if build_number.empty? && bump_build == "1"
  unique = build_numbers.values.uniq
  raise "iOS-family build numbers differ: #{build_numbers}" unless unique.length == 1
  build_number = (unique.first.to_i + 1).to_s
end

current_target = nil
updated = lines.map do |line|
  current_target = Regexp.last_match(1) if line =~ /^  ([A-Za-z0-9_]+):\s*$/
  if targets.include?(current_target)
    line = line.sub(/^        CURRENT_PROJECT_VERSION:\s*"[^"]+"/, "        CURRENT_PROJECT_VERSION: \"#{build_number}\"") unless build_number.empty?
    line = line.sub(/^        MARKETING_VERSION:\s*"[^"]+"/, "        MARKETING_VERSION: \"#{marketing_version}\"") unless marketing_version.empty?
  end
  line
end

File.write(path, updated.join)
puts "Updated #{targets.join(", ")}#{marketing_version.empty? ? "" : " marketing version to #{marketing_version}"}#{build_number.empty? ? "" : " build to #{build_number}"}"
RUBY

  (cd "$ROOT" && xcodegen generate)
}

upload_ipa() {
  local ipa="$1"
  require_file "$ipa" "IPA"
  require_file "$ASC_API_PRIVATE_KEY_PATH" "App Store Connect private key"

  xcrun altool --upload-app \
    --type ios \
    --file "$ipa" \
    --api-key "$ASC_API_KEY_ID" \
    --api-issuer "$ASC_API_ISSUER_ID" \
    --p8-file-path "$ASC_API_PRIVATE_KEY_PATH" \
    --show-progress
}

if [[ -n "$IPA_PATH" ]]; then
  upload_ipa "$IPA_PATH"
  exit 0
fi

require_file "$EXPORT_OPTIONS_PLIST" "export options plist"
update_versions_if_needed

mkdir -p "$ROOT/build"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

cd "$ROOT"

xcodebuild -project Ping.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  archive

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
  -allowProvisioningUpdates

upload_ipa "$EXPORT_PATH/${SCHEME}.ipa"
