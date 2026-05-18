#!/usr/bin/env bash
# One-time: generate the EdDSA keypair Sparkle uses to sign updates.
# The private key is stored in the macOS Keychain (login).
# The public key is printed; paste it into project.yml under SUPublicEDKey.

set -euo pipefail

cd "$(dirname "$0")/.."

# Make sure SPM has downloaded Sparkle so the CLI tools are on disk.
if [ ! -d "build/SourcePackages/artifacts/sparkle" ]; then
  echo "Resolving Sparkle via SPM…"
  xcodegen generate >/dev/null
  xcodebuild \
    -project Ping.xcodeproj \
    -scheme Ping \
    -configuration Debug \
    -derivedDataPath build \
    -resolvePackageDependencies >/dev/null
fi

# shellcheck disable=SC1091
source scripts/sparkle-tools-path.sh

GENERATE_KEYS="$SPARKLE_BIN/generate_keys"
if [ ! -x "$GENERATE_KEYS" ]; then
  echo "generate_keys not found at $GENERATE_KEYS" >&2
  exit 1
fi

echo
echo "Generating Sparkle EdDSA keypair (private key → login Keychain)…"
echo
"$GENERATE_KEYS" --account com.youngminpark.ping.Ping
echo
echo "→ Copy the public key printed above into project.yml under SUPublicEDKey, then run xcodegen generate."
