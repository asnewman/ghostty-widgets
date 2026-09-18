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
   zig build -Demit-macos-app=false
   ```

2. **Build and run macOS app:**
   ```bash
   ./run.sh
   ```
   Or open `macos/Ghostty.xcodeproj` in Xcode.

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
