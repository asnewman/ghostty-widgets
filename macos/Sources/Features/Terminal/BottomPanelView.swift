import SwiftUI
import os

/// Container model and state for the Ghostty widget bottom panel (chin).
final class BottomPanelModel: ObservableObject {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "herdr-widget")
    @Published var panelHeight: CGFloat = 32

    /// The pwd of the focused Ghostty surface, as reported by the outer shell.
    @Published var pwd: String? {
        didSet { refreshEffectivePwd() }
    }

    /// The directory the widgets should describe. While the focused surface's
    /// foreground process is a Herdr client, this is the cwd of Herdr's
    /// focused pane; otherwise it is the surface `pwd`.
    @Published private(set) var effectivePwd: String?

    /// Returns the foreground PID of the currently focused surface.
    /// Set by TerminalView whenever focus changes.
    var foregroundPIDProvider: (() -> Int?)?

    private var herdrCwd: String?
    private var herdrTimer: Timer?
    private var herdrFetchInFlight = false
    private var herdrClientPID: Int?
    private var herdrSessionName: String?
    private var herdrIsRemoteSession = false
    private var herdrExecutable: String?
    private var herdrExecutableResolved = false
    private var lastHerdrLogState: String?

    deinit {
        herdrTimer?.invalidate()
    }

    // MARK: - Herdr monitoring

    /// Starts polling Herdr for its focused pane's cwd. Only queries the
    /// server while the focused surface actually runs a Herdr client, so
    /// plain shells and other windows are unaffected.
    func startHerdrMonitoring() {
        guard herdrTimer == nil else { return }
        pollHerdr()
        herdrTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollHerdr()
        }
    }

    func stopHerdrMonitoring() {
        herdrTimer?.invalidate()
        herdrTimer = nil
        herdrClientPID = nil
        setHerdrCwd(nil)
    }

    /// Logs Herdr monitor state transitions (not every poll).
    private func logHerdrState(_ state: String) {
        guard state != lastHerdrLogState else { return }
        lastHerdrLogState = state
        Self.logger.log("\(state, privacy: .public)")
    }

    private func pollHerdr() {
        guard let pgid = foregroundPIDProvider?() else {
            logHerdrState("probe: no foreground pid (provider \(foregroundPIDProvider == nil ? "unset" : "returned nil"))")
            herdrClientPID = nil
            setHerdrCwd(nil)
            return
        }
        // The foreground PID is a process *group* ID, and the Herdr client
        // is not necessarily its leader (e.g. Ghostty's `login` wrapper), so
        // look for the client among all group members.
        let members = HerdrCLI.processGroupMembers(pgid)
        guard let clientPID = HerdrCLI.herdrClientPID(among: members) else {
            let names = members.map { "\($0.pid):\($0.executableName ?? "?")" }.joined(separator: ",")
            logHerdrState("probe: pgroup \(pgid) [\(names)] has no herdr client")
            herdrClientPID = nil
            setHerdrCwd(nil)
            return
        }

        // Resolve how this client attaches (named/remote session) once per
        // client process; the flags do not change over its lifetime.
        if clientPID != herdrClientPID {
            herdrClientPID = clientPID
            let commandLine = HerdrCLI.commandLine(forPID: clientPID) ?? ""
            herdrSessionName = HerdrCLI.sessionName(commandLine: commandLine)
            herdrIsRemoteSession = HerdrCLI.usesRemoteSession(commandLine: commandLine)
            logHerdrState("detected herdr client pid \(clientPID) session \(herdrSessionName ?? "default") remote \(herdrIsRemoteSession)")
        }

        // Remote pane cwds are paths on another machine; keep the local pwd.
        guard !herdrIsRemoteSession, !herdrFetchInFlight else { return }
        if !herdrExecutableResolved {
            herdrExecutable = HerdrCLI.locateExecutable()
            herdrExecutableResolved = true
        }
        guard let executable = herdrExecutable else { return }

        herdrFetchInFlight = true
        let sessionName = herdrSessionName
        Task.detached(priority: .utility) { [weak self] in
            let result = HerdrCLI.fetchFocusedCwd(executable: executable, sessionName: sessionName)
            await MainActor.run {
                self?.herdrFetchInFlight = false
                // Keep the last pane cwd on transient query failures; a
                // successful query with no focused pane clears the override.
                if result.ok {
                    self?.logHerdrState("fetch ok: focused pane cwd \(result.cwd ?? "none")")
                    self?.setHerdrCwd(result.cwd)
                } else {
                    self?.logHerdrState("fetch failed (exe \(executable))")
                }
            }
        }
    }

    private func setHerdrCwd(_ cwd: String?) {
        guard cwd != herdrCwd else { return }
        herdrCwd = cwd
        refreshEffectivePwd()
    }

    private func refreshEffectivePwd() {
        let resolved = herdrCwd ?? pwd
        if resolved != effectivePwd {
            effectivePwd = resolved
            logHerdrState("effectivePwd -> \(resolved ?? "nil") (herdr: \(herdrCwd ?? "nil"), surface: \(pwd ?? "nil"))")
        }
    }
}

/// The SwiftUI bottom panel component ("chin") embedded below Ghostty's terminal view.
struct BottomPanelView: View {
    @ObservedObject var model: BottomPanelModel
    @StateObject private var gitModel = GitBranchModel()
    @StateObject private var gitStatusModel = GitStatusModel()

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            GitBranchWidget(model: gitModel)
            GitStatusWidget(model: gitStatusModel) {
                gitStatusModel.refresh()
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: model.panelHeight)
        .background(.ultraThinMaterial)
        .onChange(of: model.effectivePwd) { newPwd in
            gitModel.update(for: newPwd)
            gitStatusModel.update(for: newPwd)
        }
        .onAppear {
            model.startHerdrMonitoring()
            gitModel.update(for: model.effectivePwd)
            gitStatusModel.update(for: model.effectivePwd)
        }
        .onDisappear {
            model.stopHerdrMonitoring()
        }
    }
}
