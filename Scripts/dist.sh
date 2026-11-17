#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/StageFit.app"
if [[ ! -d "$APP" ]]; then
  echo 'StageFit.app is missing. Run make build first.' >&2
  exit 1
fi
mkdir -p "$ROOT/dist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
OUTPUT="$ROOT/dist/StageFit-$VERSION-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT"
printf 'Packaged: %s\n' "$OUTPUT"
