#!/usr/bin/env bash
# Local driver for the Mac connector (run from Git Bash / WSL with gh logged in).
#
#   ios/scripts/sim.sh                         wait for the push-triggered run of HEAD
#   ios/scripts/sim.sh --screens home,log      dispatch a run on the current branch
#   ios/scripts/sim.sh --device "iPhone SE (3rd generation)" --screens home
#   ios/scripts/sim.sh --screens dashboard --scenario calibration   mock fixture scenario
#   ios/scripts/sim.sh --screens home --mock 0                      real API (sign-in screen)
#   ios/scripts/sim.sh --run 123456789         just fetch an existing run
#   --out DIR                                  where to download (default ios/out-ci)
#
# The runs live in the public mirror jafr03002/intent-ios (see .github/workflows/
# ios-mirror.yml): a push here is copied there within ~30s, as a commit titled
# "<subject> [src <sha12>]", and that push triggers the simulator run. Dispatch needs
# the workflow on the mirror's default branch (GitHub rule). Downloads the "ios-sim"
# artifact and prints summary.md.
set -euo pipefail

WORKFLOW="ios-simulator.yml"
REPO="${INTENT_IOS_REPO:-jafr03002/intent-ios}"
ROOT=$(git rev-parse --show-toplevel)
OUT="$ROOT/ios/out-ci"
SCREENS="" DEVICE="" RUN_ID="" SCENARIO="" MOCK=""
while [ $# -gt 0 ]; do
  case "$1" in
    --screens) SCREENS="$2"; shift 2 ;;
    --device)  DEVICE="$2"; shift 2 ;;
    --run)     RUN_ID="$2"; shift 2 ;;
    --scenario) SCENARIO="$2"; shift 2 ;;
    --mock)    MOCK="$2"; shift 2 ;;
    --out)     OUT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

BRANCH=$(git rev-parse --abbrev-ref HEAD)
SHA=$(git rev-parse HEAD)

find_run() { # $1 = event
  # Push runs are matched by the mirror commit's "[src <sha12>]" title tag.
  local filter=". != null"
  [ "$1" = push ] && filter="(.displayTitle | contains(\"[src ${SHA:0:12}]\"))"
  gh run list -R "$REPO" --workflow "$WORKFLOW" --branch "$BRANCH" --event "$1" --limit 20 \
    --json databaseId,displayTitle,createdAt \
    --jq "[.[] | select($filter)] | sort_by(.createdAt) | last | .databaseId // empty"
}

if [ -z "$RUN_ID" ]; then
  if [ -n "$SCREENS$DEVICE$SCENARIO$MOCK" ]; then
    before=$(find_run workflow_dispatch)
    gh workflow run -R "$REPO" "$WORKFLOW" --ref "$BRANCH" -f screens="${SCREENS:-home}" -f device="$DEVICE"       -f scenario="${SCENARIO:-default}" -f mock="${MOCK:-1}"
    for _ in $(seq 1 30); do
      RUN_ID=$(find_run workflow_dispatch)
      [ -n "$RUN_ID" ] && [ "$RUN_ID" != "$before" ] && break
      RUN_ID=""; sleep 3
    done
  else
    if [ "$(git rev-parse "origin/$BRANCH" 2>/dev/null || true)" != "$SHA" ]; then
      echo "HEAD $SHA is not pushed to origin/$BRANCH - push first (or pass --screens to dispatch)." >&2
      exit 2
    fi
    for _ in $(seq 1 60); do # mirror job + trigger take ~1 min
      RUN_ID=$(find_run push); [ -n "$RUN_ID" ] && break; sleep 3
    done
  fi
  [ -z "$RUN_ID" ] && { echo "no run found for $BRANCH@${SHA:0:7} in $REPO (check the iOS mirror run in this repo)" >&2; exit 1; }
fi

echo "run $RUN_ID: $(gh run view -R "$REPO" "$RUN_ID" --json url --jq .url)"
set +e
gh run watch -R "$REPO" "$RUN_ID" --interval 15 --exit-status > /dev/null
rc=$?
set -e

rm -rf "$OUT" && mkdir -p "$OUT"
if gh run download -R "$REPO" "$RUN_ID" --name ios-sim --dir "$OUT" 2>/dev/null; then
  cat "$OUT/summary.md" 2>/dev/null || true
  echo
  echo "artifact: $OUT"
  ls "$OUT/screens" 2>/dev/null | sed 's/^/  screen: /'
else
  echo "no artifact - job log tail:"
  gh run view -R "$REPO" "$RUN_ID" --log-failed | tail -60
fi
exit $rc
