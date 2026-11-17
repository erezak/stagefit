#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# The pure geometry code can be tested without macOS or Accessibility grants.
swiftc -swift-version 5 \
  "$ROOT/Sources/StageFit/WindowLayout.swift" \
  "$ROOT/Tests/main.swift" \
  -o "$TMP_DIR/stagefit-layout-tests"
"$TMP_DIR/stagefit-layout-tests"
