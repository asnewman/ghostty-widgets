import SwiftUI
import Foundation
import AppKit
import CoreServices

/// State model reporting working-tree stats for a directory: files changed + added/deleted lines.
final class GitStatusModel: ObservableObject {
    @Published var fileCount: Int = 0
    @Published var added: Int = 0
    @Published var deleted: Int = 0
    @Published var isGitRepo: Bool = false
    @Published var repoPath: String?

    private var currentTask: Task<Void, Never>?
    private var currentPath: String?
    private var watchedPath: String?
    private var eventStream: FSEventStreamRef?
    private var debounceWorkItem: DispatchWorkItem?

    deinit {
        stopWatching()
    }

    func update(for path: String?) {
        guard let path = path, !path.isEmpty else {
            reset()
            return
        }
        currentPath = path
        refresh(watchFor: path)
    }

    /// Re-queries stats for the current path.
    /// Used by the file watcher and manual refresh.
    func refresh(watchFor path: String? = nil) {
        let target = path ?? currentPath
        guard let target = target, !target.isEmpty else {
            reset()
            return
        }

        currentTask?.cancel()
        currentTask = Task.detached(priority: .utility) { [weak self] in
            let stats = Self.resolveStatus(for: target)
            let toplevel = Self.resolveToplevel(for: target)
            await MainActor.run {
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    self?.fileCount = stats?.files ?? 0
                    self?.added = stats?.added ?? 0
                    self?.deleted = stats?.deleted ?? 0
                    self?.isGitRepo = (stats != nil)
                    self?.repoPath = toplevel ?? target
                }
                self?.startWatching(toplevel: toplevel)
            }
        }
    }

    func invalidate() {
        currentPath = nil
        stopWatching()
    }

    private func reset() {
        currentTask?.cancel()
        stopWatching()
        fileCount = 0; added = 0; deleted = 0; isGitRepo = false
        currentPath = nil
        repoPath = nil
    }

    /// Opens the current repo in Sublime Merge (falls back to refresh if unavailable).
    func openInSublimeMerge() {
        guard let path = repoPath ?? currentPath else { return }
        let smergePaths = ["/opt/homebrew/bin/smerge", "/usr/local/bin/smerge"]
        for cli in smergePaths where FileManager.default.isExecutableFile(atPath: cli) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: cli)
            process.arguments = [path]
            try? process.run()
            return
        }
        let repoURL = URL(fileURLWithPath: path)
        if !NSWorkspace.shared.open([repoURL],
            withAppBundleIdentifier: "com.sublimemerge",
            options: [],
            additionalEventParamDescriptor: nil,
            launchIdentifiers: nil) {
            refresh()
        }
    }

    // MARK: - File watching (FSEvents)

    /// Watches the repo toplevel so edits, staging, and commits refresh the badge.
    /// No-op when already watching the same toplevel.
    private func startWatching(toplevel: String?) {
        guard let toplevel = toplevel, !toplevel.isEmpty else {
            stopWatching()
            return
        }
        if watchedPath == toplevel, eventStream != nil { return }
        stopWatching()

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info = info else { return }
            let model = Unmanaged<GitStatusModel>.fromOpaque(info).takeUnretainedValue()
            model.scheduleDebouncedRefresh()
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [toplevel] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5, // latency: coalesce bursts (saves, builds) into one refresh
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else { return }
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
        eventStream = stream
        watchedPath = toplevel
    }

    private func stopWatching() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
        watchedPath = nil
    }

    /// Coalesces rapid event bursts; only the last one in the window refreshes.
    private func scheduleDebouncedRefresh() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.refresh() }
        debounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private struct Stats { var files: Int; var added: Int; var deleted: Int }

    private static func resolveToplevel(for path: String) -> String? {
        guard let out = runGit(arguments: ["--no-optional-locks", "-C", path, "rev-parse", "--show-toplevel"]) else {
            return nil
        }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func resolveStatus(for path: String) -> Stats? {
        let gitPath = "/usr/bin/git"
        guard FileManager.default.isExecutableFile(atPath: gitPath) else { return nil }
        // Bail if not a repo
        guard runGit(arguments: ["--no-optional-locks", "-C", path, "rev-parse", "--git-dir"]) != nil else {
            return nil
        }
        var added = 0, deleted = 0
        var trackedFiles = Set<String>()
        if let numstat = runGit(arguments: ["--no-optional-locks", "-C", path, "diff", "HEAD", "--numstat"]) {
            for line in numstat.split(separator: "\n") {
                let cols = line.split(separator: "\t")
                guard cols.count == 3 else { continue }
                added += Int(cols[0]) ?? 0
                deleted += Int(cols[1]) ?? 0
                trackedFiles.insert(String(cols[2]))
            }
        }
        var untracked = 0
        if let porcelain = runGit(arguments: ["--no-optional-locks", "-C", path, "status", "--porcelain"]) {
            for line in porcelain.split(separator: "\n") {
                if line.hasPrefix("??") { untracked += 1 }
            }
        }
        return Stats(files: trackedFiles.count + untracked, added: added, deleted: deleted)
    }

    private static func runGit(arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        } catch {
            return nil
        }
    }
}

/// Compact badge: "3 files  +152/-23" (tap to open Sublime Merge).
struct GitStatusWidget: View {
    @ObservedObject var model: GitStatusModel
    var onRefresh: (() -> Void)?

    var body: some View {
        if model.isGitRepo {
            Button(action: { model.openInSublimeMerge() }) {
                HStack(spacing: 5) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(model.fileCount) file\(model.fileCount == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    HStack(spacing: 0) {
                        Text("+\(model.added)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(model.added == 0 ? .secondary : .green)
                        Text("/-\(model.deleted)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(model.deleted == 0 ? .secondary : .red)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(5)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help("Files changed: \(model.fileCount), +\(model.added)/-\(model.deleted) — click to open in Sublime Merge")
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }
}
