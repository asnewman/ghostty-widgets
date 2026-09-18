# Ghostty Widgets

> **Warning**: Work in progress. Layouts and APIs are experimental and subject to change.

A modification of [Ghostty](https://github.com/ghostty-org/ghostty) that adds a native SwiftUI widget bottom panel ("chin") to the macOS app.

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

> **Note:** Always build and run in Release mode — Debug builds are never used in this project. A Debug Zig core triggers the "You're running a debug build" warning banner (with degraded performance), and `./run.sh` defaults to the Release configuration.

## How It Works

- The bottom panel ("chin") is implemented in SwiftUI in `macos/Sources/Features/Terminal/BottomPanelView.swift`.
- It is mounted in `macos/Sources/Features/Terminal/TerminalView.swift` inside a `VStack` below the terminal split tree.
- Ghostty's existing frame listeners handle PTY column/row recalculation automatically.

## Updating from Upstream

To pull changes from upstream Ghostty:
```bash
git fetch upstream main
git rebase upstream/main
```

See [AGENTS.md](AGENTS.md) for development rules and guidelines.
