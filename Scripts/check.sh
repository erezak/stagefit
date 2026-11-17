#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for script in "$ROOT"/Scripts/*.sh; do bash -n "$script"; done

# Parsing is available on Linux and macOS; full AppKit compilation requires macOS.
if command -v swiftc >/dev/null 2>&1; then
  swiftc -frontend -parse "$ROOT"/Sources/StageFit/*.swift
fi

# plutil -lint is available on macOS; Python's plistlib also works on Linux.
if [[ "$(uname -s)" == Darwin ]]; then
  plutil -lint "$ROOT/Resources/Info.plist"
else
  python3 - "$ROOT/Resources/Info.plist" <<'PYPLIST'
import plistlib
import sys
with open(sys.argv[1], 'rb') as stream:
    p = plistlib.load(stream)
assert p['CFBundleIdentifier'] == 'dev.stagefit.macos'
assert p['LSMinimumSystemVersion'] == '13.0'
assert 'Erez Korn' in p['NSHumanReadableCopyright']
print('Info.plist OK')
PYPLIST
fi
printf 'Checks passed\n'
