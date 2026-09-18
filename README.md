# Ghostty Widgets 👻

> [!WARNING]
> **Work in Progress**: This project is under active experimental development. Features and internal layouts are subject to change.

Custom build of [Ghostty](https://github.com/ghostty-org/ghostty) featuring an integrated, collapsible native SwiftUI widget side panel on macOS.

---

## Overview

Ghostty Widgets extends Ghostty's native macOS interface by embedding a customizable widget panel along the leading edge of the terminal window. Because it integrates directly into Ghostty's SwiftUI view hierarchy, the terminal smoothly auto-resizes its column and row grid whenever the side panel expands, collapses, or resizes.

### Current Features
- 🗂 **Collapsible Side Panel**: Smooth toggle animation using native macOS `.ultraThinMaterial` styling.
- 🕒 **Live Clock Widget**: Real-time ticker built using SwiftUI's `TimelineView`.
- ⚡️ **Quick Actions**: Launchpad for frequent shell and git operations.
- 📊 **System Monitor**: Lightweight resource status cards.
- 🔄 **Upstream Compatible**: Surgical, isolated integration that rebases cleanly onto upstream Ghostty releases.

---

## Prerequisites

- **macOS**: 14.0 (Sonoma) or newer
- **Xcode**: 15.0+ or Xcode Command Line Tools
- **Zig**: (e.g. `brew install zig`) to build the underlying `GhosttyKit` framework

---

## Quick Start

### 1. Build Ghostty Core Library (First Time Only)
If building for the first time or if Zig core code changes:
```bash
zig build -Demit-macos-app=false
```

### 2. Build and Run the macOS App
Run the included build & launch script:
```bash
./run.sh
```

Or open directly in Xcode:
```bash
open macos/Ghostty.xcodeproj
```

---

## Development & Architecture

For detailed development guidelines, directory maps, and AI instructions, please see [AGENTS.md](AGENTS.md).

### Updating from Upstream Ghostty

To rebase upstream Ghostty updates without breaking your side panel:
```bash
git fetch upstream main
git rebase upstream/main
```
