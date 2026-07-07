import Foundation

enum RunError: LocalizedError {
    case emptyCommand
    case terminalUnavailable
    case terminalStartupFailure
    case commandSubmissionFailure
    case untrustedWorkspaceCancelled
    case interruptFailure
    case terminalRestartFailure

    var errorDescription: String? {
        switch self {
        case .emptyCommand:
            return "Enter a command before running."
        case .terminalUnavailable:
            return "The terminal session is not available."
        case .terminalStartupFailure:
            return "The terminal session could not be started."
        case .commandSubmissionFailure:
            return "The command could not be sent to the terminal."
        case .untrustedWorkspaceCancelled:
            return "Run was cancelled."
        case .interruptFailure:
            return "Could not send an interrupt to the terminal."
        case .terminalRestartFailure:
            return "The terminal session could not be restarted."
        }
    }
}

@MainActor
@Observable
final class RunExecutionController {
    private unowned var workspace: WorkspaceModel?
    private(set) var state: RunExecutionState = .idle
    var pendingTrustCommand: String?
    var showTrustSheet = false

    init() {}

    func bind(workspace: WorkspaceModel) {
        self.workspace = workspace
    }

    func run() {
        guard let workspace else { return }
        if state == .submitting {
            return
        }
        resetStateForNewRun()
        let command = workspace.runCommands.configuration.effectiveCommand
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            workspace.errorAlertMessage = RunError.emptyCommand.localizedDescription
            return
        }

        if !workspace.trust.isTrusted {
            pendingTrustCommand = command
            showTrustSheet = true
            return
        }

        execute(command: command)
    }

    func runOnceAfterTrustPrompt() {
        guard let command = pendingTrustCommand else { return }
        pendingTrustCommand = nil
        showTrustSheet = false
        execute(command: command)
    }

    func trustAndRun() {
        workspace?.trust.markTrusted()
        runOnceAfterTrustPrompt()
    }

    func cancelTrustPrompt() {
        pendingTrustCommand = nil
        showTrustSheet = false
    }

    func stop() {
        guard let workspace else { return }
        guard state.isInterruptible else { return }

        workspace.terminal.sendInterrupt()
        state = .interruptSent

        if workspace.runCommands.configuration.revealTerminalOnRun {
            workspace.isTerminalVisible = true
            workspace.terminal.setPanelVisible(true)
        }
        workspace.terminal.focusTerminal()
    }

    func resetStateForNewRun() {
        state = .idle
    }

    private func execute(command: String) {
        guard let workspace else { return }

        state = .submitting
        let config = workspace.runCommands.configuration

        if config.revealTerminalOnRun {
            workspace.isTerminalVisible = true
            workspace.terminal.setPanelVisible(true)
        }

        if config.clearTerminalBeforeRun {
            workspace.terminal.clearDisplay()
        }

        workspace.terminal.startIfNeeded()
        workspace.terminal.focusTerminal()
        workspace.terminal.sendCommand(command)

        state = .possiblyRunning
        AppLog.run.info("Run command dispatched to terminal session")
    }
}
