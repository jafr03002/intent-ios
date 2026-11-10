#!/usr/bin/env bash
# Put the Mac-built app on Jakob's iPhone (run from Git Bash on Windows).
#
#   bash ios/scripts/phone.sh              newest ios-ipa built for HEAD of this branch
#   bash ios/scripts/phone.sh --run <id>   a specific GitHub Actions run
#
# GitHub's macOS runner builds an unsigned Intent.ipa (xtool can't build Clerk's
# resources on Linux); `xtool install` in WSL signs it with the free Apple ID and
# installs it. Before running: phone plugged in + unlocked, then (admin, once per
# boot) `usbipd attach --wsl --busid <id>` and in WSL `sudo systemctl start usbmuxd`.
# See the memory note on xtool if it hangs at "[Connecting]".
set -euo pipefail

WORKFLOW="ios-simulator.yml"
REPO="${INTENT_IOS_REPO:-jafr03002/intent-ios}" # public CI mirror, see ios-mirror.yml
ROOT=$(git rev-parse --show-toplevel)
RUN_ID=""
[ "${1:-}" = "--run" ] && RUN_ID="$2"

if [ -z "$RUN_ID" ]; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD)
  SHA=$(git rev-parse HEAD)
  # The mirror commit for this source commit is titled "<subject> [src <sha12>]".
  RUN_ID=$(gh run list -R "$REPO" --workflow "$WORKFLOW" --branch "$BRANCH" --event push --limit 20 \
    --json databaseId,displayTitle,status \
    --jq "[.[] | select((.displayTitle | contains(\"[src ${SHA:0:12}]\")) and .status == \"completed\")] | first | .databaseId // empty")
  [ -z "$RUN_ID" ] && { echo "no finished run for $BRANCH@${SHA:0:7}; push and wait for it (bash ios/scripts/sim.sh)" >&2; exit 1; }
fi

DEST="$ROOT/ios/out-ipa"
rm -rf "$DEST" && mkdir -p "$DEST"
gh run download -R "$REPO" "$RUN_ID" --name ios-ipa --dir "$DEST"
echo "ipa from run $RUN_ID (commit $(cat "$DEST/commit.txt" | cut -c1-7))"

WSL_IPA=$(wsl -d Ubuntu -- wslpath -a "$(cygpath -m "$DEST/Intent.ipa")" | tr -d '\r')
wsl -d Ubuntu -- bash -lc "~/.local/bin/xtool install --usb '$WSL_IPA'"
