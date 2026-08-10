#!/usr/bin/env bash
# Print the app's bundle identifier, from the one place that defines it.
# Honours a gitignored Config/Identity.local.xcconfig override, exactly as the
# build does, so tooling never disagrees with what was actually installed.
#   APP=$(scripts/bundle-id.sh)   KB=$APP.keyboard
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
value=$(grep -hE '^[[:space:]]*OBADH_APP_BUNDLE_ID[[:space:]]*=' \
  "$ROOT/Config/Identity.xcconfig" "$ROOT/Config/Identity.local.xcconfig" 2>/dev/null \
  | tail -1 | sed -E 's/.*=[[:space:]]*//' | tr -d '[:space:]')
echo "${value:?OBADH_APP_BUNDLE_ID not found in Config/Identity.xcconfig}"
