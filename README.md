# Ghostty Widgets

> This is a work in progress.

A modification of [Ghostty](https://github.com/ghostty-org/ghostty) that adds a widget bottom panel. Only targeting macOS right now.

## Prerequisites

- macOS 14.0+
- Xcode 15+
- [Zig](https://ziglang.org/download/) (`brew install zig`)

## Quick Start

1. **Build Ghostty core (first time only):**
   ```bash
   zig build -Doptimize=ReleaseFast -Demit-macos-app=false
   ```
   The `ReleaseFast` flag is required: a Debug-built core shows a "You're running a debug build" banner with degraded performance.

2. **Build and run macOS app:**
   ```bash
   ./run.sh
   ```
   This builds and launches the Release app. Or open `macos/Ghostty.xcodeproj` in Xcode (use the Release scheme).

> **Note:** I always build and run in Release mode because there's no need for debug mode of Ghostty.

## Updating from Upstream

To pull changes from upstream Ghostty:
```bash
git fetch upstream main
git rebase upstream/main
```

See [AGENTS.md](AGENTS.md) for development rules and guidelines.
