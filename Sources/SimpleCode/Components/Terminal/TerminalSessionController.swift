import Foundation
import SwiftTerm

/// Lifecycle state for one terminal session, deliberately factored out of any
/// SwiftTerm type so it can be unit tested without a live view (see requirement to
/// test "terminal-session lifecycle state where it can be separated from SwiftTerm's
/// view").
enum TerminalLifecycleState: Equatable, Sendable {
    case notStarted
    case running
    case terminated(exitCode: Int32?)
}

/// Owns the intent (start / interrupt / terminate) for exactly one interactive
/// terminal session. Does not own PTY plumbing directly — that lives inside
/// SwiftTerm's `LocalProcessTerminalView`/`LocalProcess`, which this controller
/// drives through `TerminalRepresentable`.
///
/// Per the corrected product requirement (superseding the architecture report's
/// managed-PTY-per-run design): this is the single, persistent, interactive shell
/// session for a workspace. Run commands write into this same session rather than
/// spawning a second PTY.
@MainActor
@Observable
final class TerminalSessionController: TerminalCommandSending {
    let workingDirectory: URL
    private(set) var state: TerminalLifecycleState = .notStarted
    private(set) var lastKnownCols = 80
    private(set) var lastKnownRows = 24
    var isPanelVisible = true
    private(set) var needsFocus = false

    private weak var terminalView: LocalProcessTerminalView?
    private var isRestartPending = false
    private var pendingCommands: [String] = []
    var onShellTerminated: (() -> Void)?

    init(workingDirectory: URL) {
        self.workingDirectory = workingDirectory
    }

    /// Called once by `TerminalRepresentable` when the underlying AppKit view is
    /// created, so this controller can drive it without owning it.
    func attach(_ terminalView: LocalProcessTerminalView) {
        self.terminalView = terminalView
        flushPendingCommandsIfNeeded()
    }

    func startIfNeeded() {
        guard state == .notStarted else { return }
        guard let terminalView else { return }

        let shellPath = ShellEnvironment.loginShellPath()
        let environment = ShellEnvironment.makeEnvironment(workingDirectory: workingDirectory)
        let environmentArray = environment.map { "\($0.key)=\($0.value)" }

        terminalView.startProcess(
            executable: shellPath,
            environment: environmentArray,
            currentDirectory: workingDirectory.path
        )
        state = .running
        AppLog.terminal.info("Terminal session started")
        flushPendingCommandsIfNeeded()
    }

    /// Writes the exact command followed by a newline into the PTY input stream.
    func sendCommand(_ command: String) {
        let payload = command + "\n"
        guard state == .running, let terminalView else {
            pendingCommands.append(command)
            return
        }
        terminalView.send(txt: payload)
        AppLog.terminal.debug("Run command submitted")
    }

    /// Sends Ctrl-C (0x03) to the foreground process, exactly as a real terminal
    /// would when the user presses Ctrl-C.
    func sendInterrupt() {
        guard state == .running, let terminalView else { return }
        terminalView.send([0x03])
    }

    /// Terminates the shell process. `LocalProcess.terminate()` sends `SIGTERM` to
    /// the shell's PID and tears down the PTY file descriptors — this is what
    /// prevents an orphaned child shell from surviving workspace/window close.
    func terminate() {
        guard let terminalView else { return }
        terminalView.terminate()
        if state == .running {
            state = .terminated(exitCode: nil)
        }
        pendingCommands.removeAll()
    }

    /// Called by `TerminalRepresentable.Coordinator` when SwiftTerm reports that the
    /// child process terminated (whether by the user typing `exit`, a crash, or our
    /// own call to `terminate()`).
    func recordTermination(exitCode: Int32?) {
        state = .terminated(exitCode: exitCode)
        if !isRestartPending {
            onShellTerminated?()
        }
        if isRestartPending {
            isRestartPending = false
            state = .notStarted
            startIfNeeded()
        }
    }

    /// Sends the standard ANSI "clear screen + scrollback, home cursor" sequence,
    /// exactly what a real terminal's Clear command does — this does not touch the
    /// shell process itself, only what is currently displayed.
    func clearScreen() {
        terminalView?.send(txt: "\u{1B}[2J\u{1B}[3J\u{1B}[H")
    }

    func clearDisplay() {
        clearScreen()
    }

    func focusTerminal() {
        needsFocus = true
    }

    func consumeFocusRequest() -> Bool {
        guard needsFocus else { return false }
        needsFocus = false
        return true
    }

    /// Terminates the current shell and starts a fresh one in the same working
    /// directory once SwiftTerm reports the process has exited.
    func restart() {
        pendingCommands.removeAll()
        guard state == .running else {
            state = .notStarted
            startIfNeeded()
            return
        }
        isRestartPending = true
        terminalView?.terminate()
    }

    func setPanelVisible(_ visible: Bool) {
        isPanelVisible = visible
        guard visible, let terminalView, lastKnownCols > 0, lastKnownRows > 0 else { return }
        terminalView.resize(cols: lastKnownCols, rows: lastKnownRows)
    }

    func recordTerminalSize(cols: Int, rows: Int) {
        guard isPanelVisible, cols > 0, rows > 0 else { return }
        lastKnownCols = cols
        lastKnownRows = rows
    }

    private func flushPendingCommandsIfNeeded() {
        guard state == .running, terminalView != nil, !pendingCommands.isEmpty else { return }
        let commands = pendingCommands
        pendingCommands.removeAll()
        for command in commands {
            sendCommand(command)
        }
    }
}
