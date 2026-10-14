import Testing
import Foundation
@testable import Ghostty

@Suite
struct HerdrPaneListParsingTests {
    private func json(_ panes: String) -> Data {
        Data("""
        {"id":"cli:pane:list","result":{"panes":[\(panes)],"type":"pane_list"}}
        """.utf8)
    }

    @Test func returnsFocusedPaneForegroundCwd() {
        let data = json("""
        {"cwd":"/repo/a","foreground_cwd":"/repo/a/sub","focused":false,"pane_id":"w1:p1"},
        {"cwd":"/repo/b","foreground_cwd":"/repo/b","focused":true,"pane_id":"w1:p2"}
        """)
        #expect(HerdrCLI.focusedCwd(paneListJSON: data) == "/repo/b")
    }

    @Test func prefersForegroundCwdOverPaneCwd() {
        let data = json("""
        {"cwd":"/repo","foreground_cwd":"/repo/pkg","focused":true,"pane_id":"w1:p1"}
        """)
        #expect(HerdrCLI.focusedCwd(paneListJSON: data) == "/repo/pkg")
    }

    @Test func fallsBackToPaneCwdWhenForegroundCwdEmpty() {
        let data = json("""
        {"cwd":"/repo","foreground_cwd":"","focused":true,"pane_id":"w1:p1"}
        """)
        #expect(HerdrCLI.focusedCwd(paneListJSON: data) == "/repo")
    }

    @Test func returnsNilWhenNoPaneFocused() {
        let data = json("""
        {"cwd":"/repo","foreground_cwd":"/repo","focused":false,"pane_id":"w1:p1"}
        """)
        #expect(HerdrCLI.focusedCwd(paneListJSON: data) == nil)
    }

    @Test func returnsNilForErrorEnvelopeAndGarbage() {
        #expect(HerdrCLI.focusedCwd(paneListJSON: Data(#"{"error":{"message":"boom"}}"#.utf8)) == nil)
        #expect(HerdrCLI.focusedCwd(paneListJSON: Data("not json".utf8)) == nil)
    }

    @Test func extractsSessionNameFromCommandLine() {
        #expect(HerdrCLI.sessionName(commandLine: "herdr --session work pane list") == "work")
        #expect(HerdrCLI.sessionName(commandLine: "/usr/local/bin/herdr --session=work") == "work")
        #expect(HerdrCLI.sessionName(commandLine: "herdr session attach work") == "work")
        #expect(HerdrCLI.sessionName(commandLine: "herdr") == nil)
        #expect(HerdrCLI.sessionName(commandLine: "herdr pane list") == nil)
    }

    @Test func findsHerdrClientBehindGroupLeader() {
        // Ghostty wraps surfaces in `login`, which stays group leader while
        // the Herdr client runs inside the same group.
        let members: [(pid: Int, executableName: String?)] = [
            (pid: 17667, executableName: "login"),
            (pid: 17668, executableName: "herdr"),
        ]
        #expect(HerdrCLI.herdrClientPID(among: members) == 17668)
    }

    @Test func findsHerdrClientAsGroupLeader() {
        let members: [(pid: Int, executableName: String?)] = [
            (pid: 9345, executableName: "herdr"),
        ]
        #expect(HerdrCLI.herdrClientPID(among: members) == 9345)
    }

    @Test func noHerdrClientInGroup() {
        let members: [(pid: Int, executableName: String?)] = [
            (pid: 100, executableName: "zsh"),
            (pid: 101, executableName: nil),
        ]
        #expect(HerdrCLI.herdrClientPID(among: members) == nil)
    }

    @Test func detectsRemoteSessionFromCommandLine() {
        #expect(HerdrCLI.usesRemoteSession(commandLine: "herdr --remote myhost") == true)
        #expect(HerdrCLI.usesRemoteSession(commandLine: "herdr --remote=myhost") == true)
        #expect(HerdrCLI.usesRemoteSession(commandLine: "herdr --session work") == false)
    }
}
