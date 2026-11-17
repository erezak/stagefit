#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/StageFit.app"
# Do not leave stale code or resources in the resulting app bundle.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

xcrun swiftc -O -swift-version 5 \
  -target "$(uname -m)-apple-macosx13.0" \
  -framework AppKit -framework ApplicationServices \
  -framework Carbon -framework ServiceManagement \
  "$ROOT"/Sources/StageFit/*.swift \
  -o "$APP/Contents/MacOS/StageFit"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc signing for local builds; override for a stable developer identity.
# Keep the bundle identifier unchanged for existing settings/login registration.
codesign --force --sign "${STAGEFIT_SIGNING_IDENTITY:--}" "$APP"
printf 'Built: %s\n' "$APP"
