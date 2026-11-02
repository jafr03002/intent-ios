#!/usr/bin/env bash
# Runs on the GitHub macOS runner (see ios/ci/ios-simulator.yml, installed in the intent-ios mirror), from ios/.
# Builds Intent for the iOS simulator, launches each requested screen, and writes
# everything Claude needs to debug into out/:
#   out/summary.md          toolchain, device, per-screen result
#   out/build.log           full xcodebuild output
#   out/screens/<name>.png  one screenshot per screen
#   out/logs/<name>.*.txt   app stdout/stderr per screen
#   out/os-log.txt          unified log for subsystem com.jakobfreij.Intent
#   out/crashes/            any .ips crash reports
#
# Env: SCREENS="home,log"  DEVICE="iPhone 16 Pro" (optional)  SETTLE_SECONDS=4
#      MOCK=1 (fixture backend, default)  SCENARIO=default (fixture scenario folder)
set -uo pipefail

BUNDLE_ID="com.jakobfreij.Intent"
SCREENS="${SCREENS:-home}"
DEVICE="${DEVICE:-}"
SETTLE_SECONDS="${SETTLE_SECONDS:-4}"
# Mock backend on by default (CI never signs in). MOCK=0 to hit the real API.
MOCK="${MOCK:-1}"
SCENARIO="${SCENARIO:-default}"
EXTRA_ARGS=()
[ "$MOCK" = "1" ] && EXTRA_ARGS+=(-IntentMock -IntentMockScenario "$SCENARIO")
OUT="out"
rm -rf "$OUT" && mkdir -p "$OUT/screens" "$OUT/logs" "$OUT/crashes"
SUMMARY="$OUT/summary.md"
status=0

{
  echo "# iOS simulator run"
  echo
  echo "- commit: \`${GITHUB_SHA:-local}\`"
  echo "- xcode: $(xcodebuild -version | tr '\n' ' ')"
} > "$SUMMARY"

# --- pick a simulator: named device if given, else the newest-runtime iPhone ---
UDID=$(DEVICE="$DEVICE" xcrun simctl list devices available -j | python3 -c '
import json, os, re, sys
want = os.environ.get("DEVICE", "").strip()
devices = json.load(sys.stdin)["devices"]
best = None
for runtime, devs in devices.items():
    if "iOS" not in runtime:
        continue
    version = tuple(int(x) for x in re.findall(r"\d+", runtime.split("iOS")[-1]))
    for d in devs:
        if not d["name"].startswith("iPhone"):
            continue
        if want and d["name"] != want:
            continue
        key = (version, "Pro" in d["name"] and "Max" not in d["name"], d["name"])
        if best is None or key > best[0]:
            best = (key, d["udid"], d["name"], runtime)
if best is None:
    sys.exit("no matching iPhone simulator")
print(best[1])
print(best[2], file=sys.stderr)
print(best[3], file=sys.stderr)
' 2> "$OUT/device.txt")
if [ -z "$UDID" ]; then
  echo "- device: NOT FOUND ($(cat "$OUT/device.txt"))" >> "$SUMMARY"
  xcrun simctl list devices available > "$OUT/available-devices.txt"
  exit 1
fi
echo "- device: $(head -1 "$OUT/device.txt") ($(tail -1 "$OUT/device.txt" | sed 's/.*SimRuntime\.//'))" >> "$SUMMARY"

# --- build ---
xcodegen generate --quiet
xcodebuild \
  -project Intent.xcodeproj -scheme Intent -configuration Debug \
  -destination "id=$UDID" -derivedDataPath build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build > "$OUT/build.log" 2>&1
# Ad-hoc signing: no team needed, but the app gets keychain access (Clerk needs it).
build_rc=$?
if [ $build_rc -ne 0 ]; then
  {
    echo "- build: **FAILED** (exit $build_rc)"
    echo
    echo '```'
    grep -E "error:|warning: .*Swift|\*\* BUILD" "$OUT/build.log" | head -60
    echo '```'
  } >> "$SUMMARY"
  exit 1
fi
echo "- build: ok" >> "$SUMMARY"
APP="build/Build/Products/Debug-iphonesimulator/Intent.app"

# --- boot + install ---
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b > /dev/null
xcrun simctl ui "$UDID" appearance dark || true
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 || true
xcrun simctl install "$UDID" "$APP"
START=$(date "+%Y-%m-%d %H:%M:%S")

# --- one launch + screenshot per screen ---
echo >> "$SUMMARY"
echo "| screen | result |" >> "$SUMMARY"
echo "|---|---|" >> "$SUMMARY"
IFS=',' read -ra LIST <<< "$SCREENS"
for raw in "${LIST[@]}"; do
  s=$(echo "$raw" | xargs)
  [ -z "$s" ] && continue
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  # simctl prints "<bundle id>: <pid>"; simulator apps are host processes, so ps sees them.
  # (A launchctl-list check was racy and flagged healthy apps as dead.)
  if ! launched=$(xcrun simctl launch --terminate-running-process \
        --stdout="$PWD/$OUT/logs/$s.stdout.txt" --stderr="$PWD/$OUT/logs/$s.stderr.txt" \
        "$UDID" "$BUNDLE_ID" -IntentScreen "$s" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}); then
    echo "| $s | launch failed |" >> "$SUMMARY"; status=1; continue
  fi
  pid=$(echo "$launched" | awk -F': ' '{print $2}' | tr -dc '0-9')
  sleep "$SETTLE_SECONDS"
  if [ -n "$pid" ] && ps -p "$pid" > /dev/null 2>&1; then
    xcrun simctl io "$UDID" screenshot --type=png "$OUT/screens/$s.png" > /dev/null 2>&1
    echo "| $s | ok |" >> "$SUMMARY"
  else
    xcrun simctl io "$UDID" screenshot --type=png "$OUT/screens/$s.png" > /dev/null 2>&1
    echo "| $s | **not running after ${SETTLE_SECONDS}s (crash?)** |" >> "$SUMMARY"; status=1
  fi
done

# --- logs + crash reports ---
xcrun simctl spawn "$UDID" log show --start "$START" --info --debug --style compact \
  --predicate 'subsystem == "com.jakobfreij.Intent" OR process == "Intent"' > "$OUT/os-log.txt" 2>&1 || true
find ~/Library/Logs/DiagnosticReports -name "Intent*" -newermt "$START" -exec cp {} "$OUT/crashes/" \; 2>/dev/null || true
crashes=$(ls "$OUT/crashes" | wc -l | xargs)
echo >> "$SUMMARY"
echo "- crash reports: $crashes" >> "$SUMMARY"
[ "$crashes" != "0" ] && status=1

exit $status
