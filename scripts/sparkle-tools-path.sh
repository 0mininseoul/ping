#!/usr/bin/env bash
# Locate the Sparkle CLI tools (sign_update, generate_appcast, generate_keys, BinaryDelta)
# that get downloaded by SPM into the derived data folder.
# Usage: source scripts/sparkle-tools-path.sh  → exports $SPARKLE_BIN

set -euo pipefail

SEARCH_ROOTS=(
  "build/SourcePackages/artifacts/sparkle"
  "build/Build/Products"
  "$HOME/Library/Developer/Xcode/DerivedData"
)

for root in "${SEARCH_ROOTS[@]}"; do
  if [ ! -d "$root" ]; then
    continue
  fi

  candidate="$(find "$root" -type f -name "generate_appcast" -path "*/Sparkle/bin/*" 2>/dev/null | head -n 1)"
  if [ -n "${candidate:-}" ]; then
    SPARKLE_BIN="$(dirname "$candidate")"
    export SPARKLE_BIN
    return 0 2>/dev/null || exit 0
  fi
done

echo "Sparkle CLI tools not found. Run a build first so SPM downloads the Sparkle artifact." >&2
return 1 2>/dev/null || exit 1
