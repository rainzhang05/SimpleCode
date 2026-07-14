import Foundation

/// Lifecycle state for one terminal session, deliberately factored out of any
/// SwiftTerm type so it can be unit tested without a live view (see requirement to
/// test "terminal-session lifecycle state where it can be separated from SwiftTerm's
/// view").
enum TerminalLifecycleState: Equatable, Sendable {
    case notStarted
    case running
    case terminated(exitCode: Int32?)
}

/// The tiny boundary between terminal lifecycle policy and SwiftTerm's AppKit view.
/// Keeping it local makes lifecycle behavior deterministic in tests and prevents a
/// view-recreation race from becoming a shell-management race.
@MainActor
protocol TerminalSessionDriving: AnyObject {
    var isProcessRunning: Bool { get }

    func startProcess(executable: String, environment: [String], currentDirectory: String)
    @discardableResult func send(text: String) -> Bool
    @discardableResult func send(bytes: [UInt8]) -> Bool
    @discardableResult func focus() -> Bool
    func terminate()
    func resize(cols: Int, rows: Int)
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
    var isPanelVisible = false
    private(set) var needsFocus = false

    private weak var driver: (any TerminalSessionDriving)?
    private var attachmentID: UUID?
    private var startRequested = false
    private var isRestarting = false
    private var clearRequested = false
    private var pendingCommands: [String] = []
    var onShellTerminated: (() -> Void)?
    var onQueuedCommandDelivery: ((String, TerminalCommandSubmissionResult) -> Void)?

    init(workingDirectory: URL) {
        self.workingDirectory = workingDirectory
    }

    /// Called by `TerminalRepresentable` when its AppKit view is created. The
    /// controller intentionally keeps a weak driver: view recreation must never
    /// prolong the terminal view's lifetime. If SwiftUI replaces a host while a
    /// shell is active, close the old PTY before accepting the new driver so the
    /// discarded view cannot leave an orphan shell behind.
    @discardableResult
    func attach(_ driver: any TerminalSessionDriving) -> UUID {
        discardAttachedDriver(terminatingRunningProcess: true)
        let id = UUID()
        self.driver = driver
        attachmentID = id
        fulfillClearRequestIfPossible()
        launchIfRequested()
        fulfillFocusRequestIfPossible()
        return id
    }

    func detach(_ id: UUID) {
        guard attachmentID == id else { return }
        discardAttachedDriver(terminatingRunningProcess: true)
    }

    func startIfNeeded() {
        startRequested = true
        recoverFromMissingTerminationCallbackIfNeeded()
        launchIfRequested()
    }

    private func launchIfRequested() {
        guard startRequested, let driver else { return }
        if driver.isProcessRunning {
            state = .running
            fulfillClearRequestIfPossible()
            flushPendingCommandsIfNeeded()
            return
        }

        let shellPath = ShellEnvironment.loginShellPath()
        let environment = ShellEnvironment.makeEnvironment(workingDirectory: workingDirectory)
        let environmentArray = environment.map { "\($0.key)=\($0.value)" }

        driver.startProcess(
            executable: shellPath,
            environment: environmentArray,
            currentDirectory: workingDirectory.path
        )
        state = .running
        AppLog.terminal.info("Terminal session started")
        fulfillClearRequestIfPossible()
        flushPendingCommandsIfNeeded()
    }

    /// Writes the exact command followed by a newline into the PTY input stream.
    @discardableResult
    func sendCommand(_ command: String) -> TerminalCommandSubmissionResult {
        let payload = command + "\n"
        if state != .running || driver?.isProcessRunning != true {
            startIfNeeded()
        }
        guard state == .running, let driver, driver.isProcessRunning else {
            pendingCommands.append(command)
            return .queued
        }
        fulfillClearRequestIfPossible()
        guard !clearRequested else {
            pendingCommands.append(command)
            return .queued
        }
        guard driver.send(text: payload) else { return .failed }
        AppLog.terminal.debug("Run command submitted")
        return .submitted
    }

    /// Sends Ctrl-C (0x03) to the foreground process, exactly as a real terminal
    /// would when the user presses Ctrl-C.
    @discardableResult
    func sendInterrupt() -> Bool {
        guard state == .running, let driver, driver.isProcessRunning else { return false }
        return driver.send(bytes: [0x03])
    }

    @discardableResult
    func cancelQueuedCommand(_ command: String) -> Bool {
        guard let index = pendingCommands.firstIndex(of: command) else { return false }
        pendingCommands.remove(at: index)
        return true
    }

    /// Terminates the shell process. `LocalProcess.terminate()` sends `SIGTERM` to
    /// the shell's PID and tears down the PTY file descriptors — this is what
    /// prevents an orphaned child shell from surviving workspace/window close.
    func terminate() {
        startRequested = false
        if let driver, driver.isProcessRunning {
            driver.terminate()
        }
        if state == .running {
            state = .terminated(exitCode: nil)
        }
        pendingCommands.removeAll()
        clearRequested = false
        needsFocus = false
    }

    /// Called by `TerminalRepresentable.Coordinator` when SwiftTerm reports that the
    /// child process terminated. The attachment ID discards callbacks from a view
    /// SwiftUI has already replaced.
    func recordTermination(exitCode: Int32?, from id: UUID? = nil) {
        if let id, attachmentID != id { return }
        // SwiftTerm can report the old shell's termination after `restart()` has
        // already launched a replacement in the same view. Ignore both synchronous
        // callbacks inside the restart transaction and delayed callbacks while the
        // replacement process is known to be alive.
        guard !isRestarting else { return }
        guard !(state == .running && driver?.isProcessRunning == true) else { return }
        failPendingCommands()
        state = .terminated(exitCode: exitCode)
        startRequested = false
        onShellTerminated?()
    }

    func clearDisplay() {
        clearRequested = true
        needsFocus = true
        fulfillClearRequestIfPossible()
    }

    func focusTerminal() {
        needsFocus = true
        fulfillFocusRequestIfPossible()
    }

    func consumeFocusRequest() -> Bool {
        guard needsFocus, !clearRequested else { return false }
        needsFocus = false
        return true
    }

    /// Terminates the current shell and starts a fresh one in the same working
    /// directory. SwiftTerm synchronously marks its `LocalProcess` stopped during
    /// `terminate()`, so this does not rely on an eventually delivered callback.
    func restart() {
        pendingCommands.removeAll()
        startRequested = true
        isRestarting = true
        defer { isRestarting = false }
        if let driver, driver.isProcessRunning {
            driver.terminate()
        }
        state = .notStarted
        // A restart deliberately discards the foreground process, so the run
        // controller must lose its transient "possibly running" state even when
        // SwiftTerm does not deliver its eventual termination delegate callback.
        onShellTerminated?()
        launchIfRequested()
    }

    func setPanelVisible(_ visible: Bool) {
        isPanelVisible = visible
        if visible {
            startRequested = true
            launchIfRequested()
        }
        guard visible, let driver, lastKnownCols > 0, lastKnownRows > 0 else { return }
        driver.resize(cols: lastKnownCols, rows: lastKnownRows)
    }

    func recordTerminalSize(cols: Int, rows: Int) {
        guard isPanelVisible, cols > 0, rows > 0 else { return }
        lastKnownCols = cols
        lastKnownRows = rows
    }

    private func flushPendingCommandsIfNeeded() {
        guard !pendingCommands.isEmpty else { return }
        guard !clearRequested else { return }
        guard state == .running, driver?.isProcessRunning == true else {
            failPendingCommands()
            return
        }
        while let command = pendingCommands.first {
            guard state == .running, let driver, driver.isProcessRunning else {
                failPendingCommands()
                return
            }
            pendingCommands.removeFirst()
            let payload = command + "\n"
            guard driver.send(text: payload) else {
                onQueuedCommandDelivery?(command, .failed)
                failPendingCommands()
                return
            }
            AppLog.terminal.debug("Queued run command submitted")
            onQueuedCommandDelivery?(command, .submitted)
        }
    }

    private func fulfillClearRequestIfPossible() {
        guard clearRequested, let driver else { return }
        guard driver.send(bytes: [0x15, 0x0C]) else { return }
        clearRequested = false
        fulfillFocusRequestIfPossible()
    }

    private func failPendingCommands() {
        let commands = pendingCommands
        pendingCommands.removeAll()
        for command in commands {
            onQueuedCommandDelivery?(command, .failed)
        }
    }

    private func fulfillFocusRequestIfPossible() {
        guard needsFocus, !clearRequested, let driver else { return }
        if driver.focus() {
            needsFocus = false
        }
    }

    private func discardAttachedDriver(terminatingRunningProcess: Bool) {
        guard let currentDriver = driver else { return }

        // Reject a synchronous SwiftTerm termination callback before asking the
        // process to exit. A view replacement is not a shell exit the user asked
        // for, so preserve `startRequested` and let the replacement host relaunch.
        driver = nil
        attachmentID = nil
        if terminatingRunningProcess, currentDriver.isProcessRunning {
            currentDriver.terminate()
        }
        if state == .running {
            state = .notStarted
        }
    }

    /// SwiftTerm can occasionally lose a process-termination delegate callback
    /// during AppKit view transitions. Its process-running flag is authoritative for
    /// a new start request, allowing Run and Restart to self-heal instead of leaving
    /// the terminal stuck in `.running`.
    private func recoverFromMissingTerminationCallbackIfNeeded() {
        guard state == .running, driver?.isProcessRunning == false else { return }
        failPendingCommands()
        state = .terminated(exitCode: nil)
        onShellTerminated?()
    }
}
