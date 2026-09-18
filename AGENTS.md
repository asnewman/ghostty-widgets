# AGENTS.md

Welcome AI agents and contributors! This document outlines the architecture, coding guidelines, development workflows, and constraints for modifying the Ghostty Widgets project.

---

## 1. Project Overview & Architecture

This repository is a fork / custom branch of **Ghostty** (the terminal emulator created by Mitchell Hashimoto).
The core objective is to add a native, extensible **SwiftUI Widget Side Panel** to the macOS client (`macos/`) while remaining lightweight and cleanly rebaseable against upstream Ghostty (`main`).

### Key Principles
1. **Frontend Isolation**:
   - Terminal emulation, PTY logic, VT parsing, and GPU rendering remain entirely inside Ghostty's core Zig engine (`src/`).
   - All widget and sidebar logic lives strictly in macOS Swift / SwiftUI (`macos/Sources/Features/Terminal/`).
   - Do **NOT** modify Zig core files unless explicitly requested.
2. **Minimal Upstream Touchpoints**:
   - Keep changes to existing Ghostty files (like `TerminalView.swift`) down to minimal wrapper lines.
   - All new widgets and UI modules should live in their own modular Swift files (e.g. `SidePanelView.swift` or dedicated widget files).
3. **Resizing Contract**:
   - Ghostty relies on AppKit / SwiftUI frame observers to resize its PTY surfaces.
   - Any modifications to the sidebar width or visibility will trigger standard SwiftUI layout passes; Ghostty handles the terminal column/row math automatically.

---

## 2. Directory Structure & Key Files

```
macos/
├── Sources/
│   └── Features/
│       └── Terminal/
│           ├── SidePanelView.swift      # Side panel UI, state model (SidePanelModel), and widgets
│           ├── TerminalView.swift       # Ghostty's root SwiftUI terminal view (wraps split tree & side panel)
│           ├── TerminalController.swift # Main window controller
│           └── TerminalViewContainer.swift # NSView container for glass/window chrome
├── Ghostty.xcodeproj                   # Xcode project
└── build/                              # Local build output directory (gitignored)
run.sh                                  # Automation script to compile & launch the debug app
```

---

## 3. Development Workflow & Commands

### Building and Running Swift / UI Changes
When only `.swift` files are modified:
```bash
./run.sh
```
Or manually via `xcodebuild`:
```bash
xcodebuild \
  -project macos/Ghostty.xcodeproj \
  -scheme Ghostty \
  -configuration Debug \
  SYMROOT="$(pwd)/macos/build" \
  build

killall Ghostty 2>/dev/null || true
open macos/build/Debug/Ghostty.app
```

### When Zig Core or Dependencies Change
If upstream changes touch the Zig core or `GhosttyKit`:
```bash
zig build -Demit-macos-app=false
```
Then re-run `./run.sh`.

---

## 4. Coding Conventions for Widgets

- **SwiftUI Material & Styling**:
  - Use `.ultraThinMaterial` or `Color(NSColor.windowBackgroundColor)` for background surfaces to blend seamlessly with macOS vibrancy and Ghostty's background transparency settings.
- **State Management**:
  - Keep state cleanly separated in `ObservableObject` classes (e.g. `SidePanelModel`).
- **Performance**:
  - Avoid heavy background loops or non-debounced polling in widgets. For time-based animations or clocks, use SwiftUI's `TimelineView`.
- **Modularity**:
  - Create small, composable widget components conforming to `View`.

---

## 5. Syncing with Upstream

To sync new features and fixes from upstream Ghostty:
```bash
git fetch upstream main
git rebase upstream/main
```
If merge conflicts occur in `TerminalView.swift`, ensure that the `HStack(spacing: 0)` wrapper around `TerminalSplitTreeView` is preserved.
