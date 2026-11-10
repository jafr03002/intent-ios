#!/usr/bin/env bash
# Runs on the GitHub macOS runner, from ios/ (after xcodegen generate).
# Builds an UNSIGNED device .ipa into out-ipa/Intent.ipa. It is signed on Windows
# by `xtool install` with Jakob's free Apple ID (see ios/scripts/phone.sh).
# Why: xtool can't build Clerk's .xcstrings/.xcassets on Linux, so the Mac builds
# and xtool only signs + installs.
set -euo pipefail

rm -rf out-ipa && mkdir -p out-ipa
xcodebuild \
  -project Intent.xcodeproj -scheme Intent -configuration Debug \
  -destination "generic/platform=iOS" -derivedDataPath build-device \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build > out-ipa/build-device.log 2>&1 || {
    grep -E "error:|\*\* BUILD" out-ipa/build-device.log | head -40
    exit 1
  }

APP="build-device/Build/Products/Debug-iphoneos/Intent.app"
STAGE=$(mktemp -d)
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
(cd "$STAGE" && zip -qry Intent.ipa Payload)
mv "$STAGE/Intent.ipa" out-ipa/Intent.ipa
echo "${GITHUB_SHA:-local}" > out-ipa/commit.txt
ls -la out-ipa
