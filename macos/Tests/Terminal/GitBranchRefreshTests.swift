import Foundation
import Testing
@testable import Ghostty

@Suite
struct GitBranchRefreshTests {
    @Test @MainActor
    func refreshesAfterExternalCheckout() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("repo").path
        let worktree = root.appendingPathComponent("worktree").path
        try git("init", "-b", "main", repo)
        try git("-C", repo, "-c", "user.name=Test", "-c", "user.email=test@example.com",
                "commit", "--allow-empty", "-m", "initial")
        let model = GitBranchModel()
        defer { model.update(for: nil) }
        model.update(for: repo)
        try await waitFor { model.currentBranch == "main" }

        try git("-C", repo, "checkout", "-b", "created")
        try await waitFor { model.currentBranch == "created" && model.branches.contains("created") }
        try git("-C", repo, "checkout", "main")
        try await waitFor { model.currentBranch == "main" }

        try git("-C", repo, "worktree", "add", "-b", "worktree-branch", worktree)
        model.update(for: worktree)
        try await waitFor { model.currentBranch == "worktree-branch" }
        try git("-C", worktree, "checkout", "-b", "worktree-created")
        try await waitFor { model.currentBranch == "worktree-created" }
        try git("-C", worktree, "checkout", "--detach")
        try await waitFor { model.currentBranch?.hasPrefix("(") == true }

        model.update(for: repo)
        model.update(for: nil)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        #expect(model.currentBranch == nil)
        #expect(model.branches.isEmpty)
    }

    @MainActor
    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while !condition() && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try #require(condition())
    }

    private func git(_ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
    }
}
