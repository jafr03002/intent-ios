#!/usr/bin/env bash
# Regenerates the committed Swift client in ios/Packages/IntentKit/Sources/IntentAPI/Generated
# from lib/api-spec/openapi.yaml with apple/swift-openapi-generator.
#
# Runs on Linux (WSL) or macOS with a Swift 6 toolchain plus python3 + PyYAML. From Windows:
#   wsl -d Ubuntu --cd /mnt/c/<repo> -- bash -lc 'bash ios/scripts/generate-api.sh'
#
# The generator is cloned and built once into $GENERATOR_DIR (outside the repo: building on
# /mnt/c NTFS is slow). Bump GENERATOR_VERSION to upgrade; keep the runtime pins in
# ios/Packages/IntentKit/Package.swift compatible.
#
# The output is committed (no build plugin) so XcodeGen and xtool builds need no plugin trust.
set -euo pipefail

GENERATOR_VERSION="${GENERATOR_VERSION:-1.14.3}"
GENERATOR_DIR="${GENERATOR_DIR:-/tmp/intent-openapi-generator-$GENERATOR_VERSION}"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SPEC="$ROOT/lib/api-spec/openapi.yaml"
CONFIG="$ROOT/ios/scripts/openapi-generator-config.yaml"
OUT="$ROOT/ios/Packages/IntentKit/Sources/IntentAPI/Generated"

if [ ! -d "$GENERATOR_DIR/.git" ]; then
  git clone --quiet --depth 1 --branch "$GENERATOR_VERSION" \
    https://github.com/apple/swift-openapi-generator.git "$GENERATOR_DIR"
fi
swift build --package-path "$GENERATOR_DIR" -c release --product swift-openapi-generator
BIN="$(swift build --package-path "$GENERATOR_DIR" -c release --show-bin-path)/swift-openapi-generator"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# The generator rejects some valid 3.1 constructs in the spec; rewrite a temp copy
# (see openapi-preprocess.py for each workaround). The real spec stays untouched.
python3 "$ROOT/ios/scripts/openapi-preprocess.py" "$SPEC" "$TMP/openapi.yaml"
"$BIN" generate --config "$CONFIG" --output-directory "$TMP/out" "$TMP/openapi.yaml"

mkdir -p "$OUT"
rm -f "$OUT"/*.swift
cp "$TMP"/out/*.swift "$OUT"/
echo "Generated with swift-openapi-generator $GENERATOR_VERSION:"
wc -l "$OUT"/*.swift
