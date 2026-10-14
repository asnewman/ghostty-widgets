import SwiftUI
import Foundation
import CoreServices

/// State model responsible for discovering and reporting the Git branch of a directory.
final class GitBranchModel: ObservableObject {
    @Published var currentBranch: String?
    @Published var isGitRepo: Bool = false
    @Published var branches: [String] = []
    @Published var isSwitching: Bool = false
    @Published var checkoutError: String?

    private var currentTask: Task<Void, Never>?
    private var lastCheckedPath: String?
    private var repoPath: String?
    private var watchedPath: String?
    private var eventStream: FSEventStreamRef?
    private var debounceWorkItem: DispatchWorkItem?

    deinit {
        stopWatching()
    }

    func update(for path: String?) {
        guard let path = path, !path.isEmpty else {
            currentTask?.cancel()
            stopWatching()
            self.currentBranch = nil
            self.isGitRepo = false
            self.branches = []
            self.lastCheckedPath = nil
            self.repoPath = nil
            return
        }

        // Avoid re-querying if the path has not changed
        if path == lastCheckedPath && currentBranch != nil {
            return
        }
        stopWatching()
        lastCheckedPath = path
        repoPath = path
        refresh()
    }

    private func refresh() {
        guard let path = repoPath else { return }
        currentTask?.cancel()
        currentTask = Task.detached(priority: .utility) { [weak self] in
            // Resolve the actual metadata directory: .git can be a file in a worktree.
            let gitDirectory = Self.runGit(arguments: ["-C", path, "rev-parse", "--absolute-git-dir"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let branch = Self.resolveGitBranch(for: path)
            await MainActor.run {
                guard !Task.isCancelled, let self, self.repoPath == path else { return }
                self.startWatching(gitDirectory: gitDirectory)
                withAnimation(.easeInOut(duration: 0.15)) {
                    self.currentBranch = branch
                    self.isGitRepo = (branch != nil)
                }
            }
        }
    }

    /// Watch the directory rather than HEAD itself, which Git replaces atomically.
    private func startWatching(gitDirectory: String?) {
        guard let gitDirectory, !gitDirectory.isEmpty else {
            stopWatching()
            return
        }
        if watchedPath == gitDirectory, eventStream != nil { return }
        stopWatching()

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let model = Unmanaged<GitBranchModel>.fromOpaque(info).takeUnretainedValue()
            model.scheduleRefresh()
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [gitDirectory] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }
        eventStream = stream
        watchedPath = gitDirectory
        // Close the gap between the initial query and installing the watcher.
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.refresh()
            self?.refreshBranches()
        }
        debounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
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

    /// Loads local branches ordered by most recently checked out first.
    func refreshBranches() {
        guard let path = repoPath else { return }
        // Show cached list immediately while refreshing in background.
        Task.detached(priority: .utility) { [weak self] in
            let ordered = Self.resolveBranchesByRecency(for: path)
            await MainActor.run {
                guard self?.repoPath == path else { return }
                self?.branches = ordered
            }
        }
    }

    func checkout(branch: String) {
        guard let path = repoPath, branch != currentBranch else { return }
        isSwitching = true
        checkoutError = nil
        Task.detached(priority: .utility) { [weak self] in
            let error = Self.runCheckout(for: path, branch: branch)
            let newBranch = Self.resolveGitBranch(for: path)
            await MainActor.run {
                self?.isSwitching = false
                if let error {
                    self?.checkoutError = error
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        self?.currentBranch = newBranch
                    }
                    // Move the newly checked out branch to the front.
                    if let newBranch, let idx = self?.branches.firstIndex(of: newBranch) {
                        self?.branches.remove(at: idx)
                        self?.branches.insert(newBranch, at: 0)
                    } else if let newBranch {
                        self?.branches.insert(newBranch, at: 0)
                    }
                }
            }
        }
    }

    static func orderBranches(reflogLines: [String], allBranches: [String]) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()
        for line in reflogLines {
            guard line.hasPrefix("checkout: moving from ") else { continue }
            let remainder = line.dropFirst("checkout: moving from ".count)
            guard let sep = remainder.range(of: " to ") else { continue }
            let from = String(remainder[..<sep.lowerBound])
            let to = String(remainder[sep.upperBound...])
            for name in [to, from] where !name.isEmpty && !seen.contains(name) {
                seen.insert(name)
                ordered.append(name)
            }
        }
        let rest = allBranches
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !seen.contains($0) }
            .sorted()
        ordered.append(contentsOf: rest)
        // Drop reflog names that no longer exist locally.
        let local = Set(allBranches.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        return ordered.filter { local.contains($0) }
    }

    /// Orders branches by last checkout (from reflog), then appends any
    /// remaining local branches alphabetically.
    private static func resolveBranchesByRecency(for path: String) -> [String] {
        // `git reflog` records "checkout: moving from A to B" entries newest-first.
        let reflogLines = runGit(arguments: ["--no-optional-locks", "-C", path, "reflog", "--date=iso", "--format=%gs"])?
            .components(separatedBy: .newlines) ?? []
        let all = runGit(arguments: ["--no-optional-locks", "-C", path, "for-each-ref", "--format=%(refname:short)", "refs/heads/"])?
            .components(separatedBy: .newlines) ?? []
        return orderBranches(reflogLines: reflogLines, allBranches: all)
    }

    private static func runCheckout(for path: String, branch: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["--no-optional-locks", "-C", path, "checkout", branch]
        let errPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                let msg = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return msg?.isEmpty == false ? msg : "git checkout failed"
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Safely inspects the provided directory path for a Git branch without blocking the UI.
    private static func resolveGitBranch(for path: String) -> String? {
        let gitPath = "/usr/bin/git"
        guard FileManager.default.isExecutableFile(atPath: gitPath) else {
            return nil
        }

        // Try getting symbolic branch name first
        guard let branchOutput = runGit(
            arguments: ["--no-optional-locks", "-C", path, "rev-parse", "--abbrev-ref", "HEAD"]
        ) else {
            return nil
        }

        let trimmed = branchOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }

        // If in detached HEAD state, resolve the short commit hash
        if trimmed == "HEAD" {
            if let commitHash = runGit(arguments: ["--no-optional-locks", "-C", path, "rev-parse", "--short", "HEAD"]) {
                let hash = commitHash.trimmingCharacters(in: .whitespacesAndNewlines)
                return hash.isEmpty ? nil : "(\(hash))"
            }
            return "(detached)"
        }

        return trimmed
    }

    private static func runGit(arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // Suppress stderr output

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

/// A compact status badge displaying the current Git branch.
/// Clicking it opens a branch list ordered by last checkout; selecting one checks it out.
struct GitBranchWidget: View {
    @ObservedObject var model: GitBranchModel

    var body: some View {
        if let branch = model.currentBranch {
            Menu {
                if model.branches.isEmpty {
                    Text("No branches found")
                } else {
                    ForEach(model.branches, id: \.self) { name in
                        Button {
                            model.checkout(branch: name)
                        } label: {
                            HStack {
                                Text(name)
                                if name == branch {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .disabled(model.isSwitching || name == branch)
                    }
                }
            } label: {
                HStack(spacing: 7.5) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 16.5, weight: .semibold))
                    Text(branch)
                        .font(.system(size: 16.5, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                    if model.isSwitching {
                        ProgressView()
                            .scaleEffect(0.9)
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4.5)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(7.5)
                .foregroundColor(.secondary)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .help(model.checkoutError.map { "Git Branch: \(branch) — \($0)" } ?? "Git Branch: \(branch) — click to switch")
            .onTapGesture {
                // Pre-load so the menu is fresh when opened.
                model.refreshBranches()
            }
            .onAppear {
                model.refreshBranches()
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }
}
