import Testing
@testable import Ghostty

@Suite
struct GitBranchOrderingTests {
    @Test func ordersByLastCheckoutThenAlphabetical() {
        let reflog = [
            "checkout: moving from main to feature-b",
            "checkout: moving from feature-a to main",
            "commit: something unrelated",
        ]
        let all = ["feature-a", "feature-b", "main", "stale"]
        #expect(GitBranchModel.orderBranches(reflogLines: reflog, allBranches: all)
            == ["feature-b", "main", "feature-a", "stale"])
    }

    @Test func dropsDeletedBranches() {
        let reflog = ["checkout: moving from main to gone"]
        #expect(GitBranchModel.orderBranches(reflogLines: reflog, allBranches: ["main"]) == ["main"])
    }
}
