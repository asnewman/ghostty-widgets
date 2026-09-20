import SwiftUI
import Foundation

/// State model reporting working-tree stats for a directory: files changed + added/deleted lines.
final class GitStatusModel: ObservableObject {
    @Published var fileCount: Int = 0
    @Published var added: Int = 0
    @Published var deleted: Int = 0
    @Published var isGitRepo: Bool = false

    private var currentTask: Task<Void, Never>?
    private var lastCheckedPath: String?

    func update(for path: String?) {
        guard let path = path, !path.isEmpty else {
            reset()
            return
        }
        if path == lastCheckedPath { return }
        lastCheckedPath = path

        currentTask?.cancel()
        currentTask = Task.detached(priority: .utility) { [weak self] in
            let stats = Self.resolveStatus(for: path)
            await MainActor.run {
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    self?.fileCount = stats?.files ?? 0
                    self?.added = stats?.added ?? 0
                    self?.deleted = stats?.deleted ?? 0
                    self?.isGitRepo = (stats != nil)
                }
            }
        }
    }

    func invalidate() { lastCheckedPath = nil }

    private func reset() {
        currentTask?.cancel()
        fileCount = 0; added = 0; deleted = 0; isGitRepo = false
        lastCheckedPath = nil
    }

    private struct Stats { var files: Int; var added: Int; var deleted: Int }

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

/// Compact badge: "3 files  +152/-23" (tap to refresh).
struct GitStatusWidget: View {
    @ObservedObject var model: GitStatusModel
    var onRefresh: (() -> Void)?

    var body: some View {
        if model.isGitRepo {
            Button(action: { onRefresh?() }) {
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
            .help("Files changed: \(model.fileCount), +\(model.added)/-\(model.deleted)")
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }
}
