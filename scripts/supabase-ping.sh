#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

EXPECTED_PROJECT_REF="${PING_SUPABASE_PROJECT_REF:-qxjtprxvjmaxlbtljcjw}"
EXPECTED_ORG_ID="${PING_SUPABASE_ORG_ID:-nvyhcwxyemylsqjlbdpo}"
EXPECTED_PROJECT_NAME="${PING_SUPABASE_PROJECT_NAME:-Ping}"
SUPABASE_PROFILE="${PING_SUPABASE_PROFILE:-supabase}"

fail() {
  printf 'supabase-ping: %s\n' "$*" >&2
  exit 1
}

show_usage() {
  cat <<EOF
Usage: ./scripts/supabase-ping.sh <supabase-subcommand> [args...]

Runs Supabase CLI for this repo through the pinned Ping account/project guard.

Pinned project:
  ref:  ${EXPECTED_PROJECT_REF}
  org:  ${EXPECTED_ORG_ID}
  name: ${EXPECTED_PROJECT_NAME}

Pinned CLI profile:
  ${SUPABASE_PROFILE}

Override only for deliberate local maintenance:
  PING_SUPABASE_PROFILE=<profile> ./scripts/supabase-ping.sh ...
EOF
}

if [[ $# -eq 0 ]]; then
  show_usage
  exit 0
fi

case "${1:-}" in
  -h|--help|help)
    show_usage
    exit 0
    ;;
esac

for arg in "$@"; do
  case "$arg" in
    --profile|--profile=*)
      fail "do not pass --profile directly; set PING_SUPABASE_PROFILE if this repo's pinned profile changes"
      ;;
  esac
done

if [[ -n "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  fail "SUPABASE_ACCESS_TOKEN is set and could override the pinned profile; unset it before running this repo's Supabase commands"
fi

linked_ref_file="${REPO_ROOT}/supabase/.temp/project-ref"
if [[ -f "$linked_ref_file" ]]; then
  linked_ref="$(tr -d '[:space:]' < "$linked_ref_file")"
  if [[ -n "$linked_ref" && "$linked_ref" != "$EXPECTED_PROJECT_REF" ]]; then
    fail "this checkout is linked to ${linked_ref}, expected ${EXPECTED_PROJECT_REF}; run './scripts/supabase-ping.sh link --project-ref ${EXPECTED_PROJECT_REF}'"
  fi
fi

if [[ "${1:-}" == "link" ]]; then
  requested_ref=""
  previous=""
  for arg in "$@"; do
    if [[ "$previous" == "--project-ref" ]]; then
      requested_ref="$arg"
      break
    fi
    case "$arg" in
      --project-ref=*)
        requested_ref="${arg#--project-ref=}"
        break
        ;;
    esac
    previous="$arg"
  done

  if [[ -z "$requested_ref" ]]; then
    fail "link must specify the pinned project: './scripts/supabase-ping.sh link --project-ref ${EXPECTED_PROJECT_REF}'"
  fi

  if [[ "$requested_ref" != "$EXPECTED_PROJECT_REF" ]]; then
    fail "refusing to link ${requested_ref}; this repo is pinned to ${EXPECTED_PROJECT_REF}"
  fi
fi

if [[ "${1:-}" == "unlink" && "${PING_SUPABASE_ALLOW_UNLINK:-}" != "1" ]]; then
  fail "unlink is blocked for this repo; set PING_SUPABASE_ALLOW_UNLINK=1 only for deliberate maintenance"
fi

runtime_plist="${REPO_ROOT}/Resources/Supabase.plist"
if [[ -f "$runtime_plist" ]]; then
  runtime_url="$(/usr/libexec/PlistBuddy -c 'Print :SUPABASE_URL' "$runtime_plist" 2>/dev/null || true)"
  if [[ -n "$runtime_url" && "$runtime_url" != *"${EXPECTED_PROJECT_REF}.supabase.co"* ]]; then
    fail "Resources/Supabase.plist points at ${runtime_url}; expected https://${EXPECTED_PROJECT_REF}.supabase.co"
  fi
fi

projects_json="$(
  cd "$REPO_ROOT"
  npx supabase --profile "$SUPABASE_PROFILE" projects list --output-format json
)"

PROJECTS_JSON="$projects_json" /usr/bin/python3 - "$EXPECTED_PROJECT_REF" "$EXPECTED_ORG_ID" "$EXPECTED_PROJECT_NAME" <<'PY'
import json
import os
import sys

expected_ref, expected_org, expected_name = sys.argv[1:4]
payload = json.loads(os.environ["PROJECTS_JSON"])
projects = payload.get("projects", [])
match = next((p for p in projects if p.get("ref") == expected_ref), None)

if match is None:
    print(
        f"supabase-ping: profile cannot access pinned project {expected_ref}; "
        "log into the Ping Supabase account for this profile",
        file=sys.stderr,
    )
    sys.exit(1)

if match.get("organization_id") != expected_org:
    print(
        f"supabase-ping: pinned project org mismatch: {match.get('organization_id')} != {expected_org}",
        file=sys.stderr,
    )
    sys.exit(1)

if match.get("name") != expected_name:
    print(
        f"supabase-ping: pinned project name mismatch: {match.get('name')} != {expected_name}",
        file=sys.stderr,
    )
    sys.exit(1)
PY

cd "$REPO_ROOT"
exec npx supabase --profile "$SUPABASE_PROFILE" "$@"
