import SwiftUI
import Foundation

/// State model responsible for discovering and reporting the Git branch of a directory.
final class GitBranchModel: ObservableObject {
    @Published var currentBranch: String?
    @Published var isGitRepo: Bool = false

    private var currentTask: Task<Void, Never>?
    private var lastCheckedPath: String?

    func update(for path: String?) {
        guard let path = path, !path.isEmpty else {
            self.currentBranch = nil
            self.isGitRepo = false
            self.lastCheckedPath = nil
            return
        }

        // Avoid re-querying if the path has not changed
        if path == lastCheckedPath && currentBranch != nil {
            return
        }
        lastCheckedPath = path

        currentTask?.cancel()
        currentTask = Task.detached(priority: .utility) { [weak self] in
            let branch = Self.resolveGitBranch(for: path)
            await MainActor.run {
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    self?.currentBranch = branch
                    self?.isGitRepo = (branch != nil)
                }
            }
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
struct GitBranchWidget: View {
    @ObservedObject var model: GitBranchModel

    var body: some View {
        if let branch = model.currentBranch {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .semibold))
                Text(branch)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(5)
            .foregroundColor(.secondary)
            .help("Git Branch: \(branch)")
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }
}
