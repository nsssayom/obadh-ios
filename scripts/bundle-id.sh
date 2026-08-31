#!/usr/bin/env bash
# Print the app's bundle identifier, from the one place that defines it.
# Honours a gitignored Config/Identity.local.xcconfig override, exactly as the
# build does, so tooling never disagrees with what was actually installed.
#   APP=$(scripts/bundle-id.sh)   KB=$APP.keyboard
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Only search files that exist. The local override is optional, and passing a
# missing path to grep makes it exit 2, which under `pipefail` killed the whole
# script — it printed NOTHING and exited non-zero on every clean checkout. Callers
# that captured the output got an empty string: `sweep.sh` then enabled a keyboard
# called ".keyboard", so the parity sweep captured the SYSTEM keyboard eight times
# per device and reported every cell incomplete. It stayed hidden because the sweep
# devices already had Obadh enabled from before this script existed.
files=("$ROOT/Config/Identity.xcconfig")
[[ -f "$ROOT/Config/Identity.local.xcconfig" ]] && files+=("$ROOT/Config/Identity.local.xcconfig")
value=$(grep -hE '^[[:space:]]*OBADH_APP_BUNDLE_ID[[:space:]]*=' "${files[@]}" \
  | tail -1 | sed -E 's/.*=[[:space:]]*//' | tr -d '[:space:]')
echo "${value:?OBADH_APP_BUNDLE_ID not found in Config/Identity.xcconfig}"
