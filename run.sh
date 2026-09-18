#!/usr/bin/env bash
set -e

# Resolve root directory regardless of where script is run from
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$ROOT_DIR/macos"
SYMROOT="$MACOS_DIR/build"
APP_PATH="$SYMROOT/Debug/Ghostty.app"

echo "==> Building Ghostty (Debug)..."
xcodebuild \
  -project "$MACOS_DIR/Ghostty.xcodeproj" \
  -scheme Ghostty \
  -configuration Debug \
  SYMROOT="$SYMROOT" \
  build

echo "==> Restarting Ghostty..."
killall Ghostty 2>/dev/null || true
sleep 0.5
open "$APP_PATH"

echo "==> Ghostty launched successfully!"
