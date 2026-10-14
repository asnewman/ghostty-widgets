import Foundation

/// Queries a running Herdr server through the `herdr` CLI.
///
/// Herdr panes live inside the Herdr server, so the outer Ghostty surface
/// only ever reports the cwd of the shell that launched the Herdr client.
/// Asking the server for its focused pane is how the widget bar learns the
/// directory the user is actually working in.
enum HerdrCLI {
    // MARK: - Pane list parsing

    private struct PaneListResponse: Decodable {
        struct Result: Decodable {
            struct Pane: Decodable {
                let focused: Bool?
                let cwd: String?
                let foregroundCwd: String?

                enum CodingKeys: String, CodingKey {
                    case focused
                    case cwd
                    case foregroundCwd = "foreground_cwd"
                }
            }

            let panes: [Pane]
        }

        let result: Result?
    }

    /// Returns the cwd of the focused pane in a `herdr pane list` response,
    /// preferring the foreground process's cwd over the pane's tracked cwd.
    static func focusedCwd(paneListJSON data: Data) -> String? {
        guard let response = try? JSONDecoder().decode(PaneListResponse.self, from: data),
              let pane = response.result?.panes.first(where: { $0.focused == true }) else {
            return nil
        }
        if let foreground = pane.foregroundCwd, !foreground.isEmpty {
            return foreground
        }
        guard let cwd = pane.cwd, !cwd.isEmpty else { return nil }
        return cwd
    }

    // MARK: - Client command line parsing

    /// Extracts the `--session` value from a Herdr client command line, if any.
    static func sessionName(commandLine: String) -> String? {
        let tokens = commandLine.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        for (index, token) in tokens.enumerated() {
            if token == "--session", index + 1 < tokens.count {
                return tokens[index + 1]
            }
            if token.hasPrefix("--session=") {
                let name = String(token.dropFirst("--session=".count))
                return name.isEmpty ? nil : name
            }
            // `herdr session attach <name>` form.
            if token == "attach", index >= 1, tokens[index - 1] == "session",
               index + 1 < tokens.count {
                return tokens[index + 1]
            }
        }
        return nil
    }

    /// True when a Herdr client command line attaches to a remote session.
    /// Remote pane cwds are paths on another machine, so they must never be
    /// fed to the local git widgets.
    static func usesRemoteSession(commandLine: String) -> Bool {
        commandLine.split(whereSeparator: { $0.isWhitespace }).contains {
            $0 == "--remote" || $0.hasPrefix("--remote=")
        }
    }

    // MARK: - Process inspection

    /// Returns the PIDs of every process in a process group.
    static func processIDsInGroup(_ pgid: Int) -> [Int] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PGRP, Int32(pgid)]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
            return []
        }
        var processes = [kinfo_proc](
            repeating: kinfo_proc(),
            count: size / MemoryLayout<kinfo_proc>.stride)
        guard sysctl(&mib, u_int(mib.count), &processes, &size, nil, 0) == 0 else {
            return []
        }
        return processes
            .prefix(size / MemoryLayout<kinfo_proc>.stride)
            .map { Int($0.kp_proc.p_pid) }
    }

    /// PIDs and executable names of every process in a process group.
    static func processGroupMembers(_ pgid: Int) -> [(pid: Int, executableName: String?)] {
        processIDsInGroup(pgid).map { (pid: $0, executableName: executableName(forPID: $0)) }
    }

    /// Returns the first group member running the Herdr client, if any.
    /// The client is not always the group leader: Ghostty wraps surfaces in
    /// `login`, and shells without job control run jobs in their own group,
    /// so the whole foreground group has to be checked.
    static func herdrClientPID(among members: [(pid: Int, executableName: String?)]) -> Int? {
        members.first { $0.executableName == "herdr" }?.pid
    }

    /// Returns the executable file name (e.g. "herdr") for a process ID.
    static func executableName(forPID pid: Int) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid_t(pid), &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let path = String(cString: buffer)
        return path.isEmpty ? nil : URL(fileURLWithPath: path).lastPathComponent
    }

    /// Returns the full command line for a process ID (via `ps`).
    static func commandLine(forPID pid: Int) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "args="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let line = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return line?.isEmpty == false ? line : nil
        } catch {
            return nil
        }
    }

    // MARK: - Live query

    /// Locates the `herdr` executable. GUI apps get a minimal PATH, so the
    /// usual install locations are checked explicitly.
    static func locateExecutable() -> String? {
        var candidates: [String] = []
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/herdr" }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        candidates += [
            "\(home)/.local/bin/herdr",
            "/opt/homebrew/bin/herdr",
            "/usr/local/bin/herdr",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs `herdr pane list` and returns the focused pane's cwd.
    /// `ok` is false when the query itself failed (no server, CLI error), in
    /// which case callers should keep whatever value they already had.
    static func fetchFocusedCwd(executable: String, sessionName: String?) -> (ok: Bool, cwd: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        var arguments: [String] = []
        if let sessionName {
            arguments += ["--session", sessionName]
        }
        arguments += ["pane", "list"]
        process.arguments = arguments

        // The app itself is never launched from inside a Herdr pane, but if
        // it was (e.g. during development), the inherited caller context must
        // not leak into this query.
        var environment = ProcessInfo.processInfo.environment
        for key in ["HERDR_ENV", "HERDR_WORKSPACE_ID", "HERDR_TAB_ID", "HERDR_PANE_ID"] {
            environment.removeValue(forKey: key)
        }
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return (false, nil)
        }

        // The local socket round-trip is normally milliseconds; never let a
        // wedged server hang the poller.
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            if process.isRunning { process.terminate() }
        }
        // Drain stdout concurrently: a large pane list could otherwise fill
        // the pipe buffer and block the CLI before it exits.
        final class DataBox { var data = Data() }
        let box = DataBox()
        let drained = DispatchGroup()
        drained.enter()
        DispatchQueue.global().async {
            box.data = pipe.fileHandleForReading.readDataToEndOfFile()
            drained.leave()
        }
        process.waitUntilExit()
        drained.wait()
        guard process.terminationStatus == 0 else { return (false, nil) }
        return (true, focusedCwd(paneListJSON: box.data))
    }
}
