#!/usr/bin/env bash
# Regenerate IntentCore's golden fixtures from the web app's TypeScript.
#
#   bash ios/scripts/core-fixtures/generate.sh
#
# Bundles generate.ts with the repo's own esbuild (no new dependency), runs it on
# node, and writes ios/Packages/IntentKit/Tests/IntentCoreTests/Fixtures/*.json.
# Re-run whenever a ported file in artifacts/traintent/src/lib (or the hooks)
# changes, then run the Swift tests: a failing parity test means the Swift port
# needs the same change.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
OUT="$ROOT/ios/Packages/IntentKit/Tests/IntentCoreTests/Fixtures"

# esbuild lives in the pnpm store. A git worktree usually has no node_modules of its
# own, so fall back to the main checkout's.
find_esbuild() {
  local base
  for base in "$ROOT" "$(cd "$(git -C "$HERE" rev-parse --git-common-dir)/.." && pwd)"; do
    local hit
    hit=$(ls -d "$base"/node_modules/.pnpm/esbuild@*/node_modules/esbuild/bin/esbuild 2>/dev/null | sort -V | tail -1 || true)
    if [ -n "$hit" ]; then echo "$hit"; return; fi
  done
}
ESBUILD="${ESBUILD:-$(find_esbuild)}"
[ -n "$ESBUILD" ] || { echo "esbuild not found - run pnpm install at the repo root (or set ESBUILD)" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cd "$ROOT"
node "$ESBUILD" "ios/scripts/core-fixtures/generate.ts" \
  --bundle --platform=node --format=esm --log-level=warning \
  --alias:@=./artifacts/traintent/src \
  --alias:react=./ios/scripts/core-fixtures/stubs.ts \
  --alias:clsx=./ios/scripts/core-fixtures/stubs.ts \
  --alias:tailwind-merge=./ios/scripts/core-fixtures/stubs.ts \
  --outfile="$TMP/generate.mjs"

TZ=UTC node "$TMP/generate.mjs" "$OUT"
