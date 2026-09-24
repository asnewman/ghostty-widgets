#!/usr/bin/env bash
set -e

# Resolve root directory regardless of where script is run from
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$ROOT_DIR/macos"
CONFIG="${1:-Release}"
SYMROOT="$MACOS_DIR/build"
APP_PATH="$SYMROOT/$CONFIG/Ghostty.app"

echo "==> Building Ghostty ($CONFIG)..."
xcodebuild \
  -project "$MACOS_DIR/Ghostty.xcodeproj" \
  -scheme Ghostty \
  -configuration "$CONFIG" \
  SYMROOT="$SYMROOT" \
  ENABLE_HARDENED_RUNTIME=NO \
  build

echo "==> Restarting Ghostty..."
killall Ghostty 2>/dev/null || true
sleep 0.5
for var in $(compgen -e); do
  case "$var" in
    HERDR_*) unset "$var" ;;
  esac
done
open "$APP_PATH"

echo "==> Ghostty launched successfully!"
