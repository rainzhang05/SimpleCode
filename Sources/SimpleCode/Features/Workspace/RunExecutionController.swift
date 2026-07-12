import Foundation

enum RunError: LocalizedError {
    case emptyCommand
    case terminalUnavailable
    case commandSubmissionFailure
    case interruptFailure

    var errorDescription: String? {
        switch self {
        case .emptyCommand:
            return "Enter a command before running."
        case .terminalUnavailable:
            return "The terminal session is not available."
        case .commandSubmissionFailure:
            return "The command could not be sent to the terminal."
        case .interruptFailure:
            return "Could not send an interrupt to the terminal."
        }
    }
}

@MainActor
@Observable
final class RunExecutionController {
    private unowned var workspace: WorkspaceModel?
    private var terminal: (any TerminalCommandSending)?
    private(set) var state: RunExecutionState = .idle
    private var queuedCommand: String?
    private var lastSubmissionDate: Date?
    private let now: () -> Date
    private let rapidRunSuppressionInterval: TimeInterval = 0.35

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func bind(
        workspace: WorkspaceModel,
        terminal: (any TerminalCommandSending)? = nil
    ) {
        self.workspace = workspace
        self.terminal = terminal ?? workspace.terminal
        self.terminal?.onQueuedCommandDelivery = { [weak self] command, result in
            self?.recordQueuedCommandDelivery(command: command, result: result)
        }
    }

    func run() {
        guard let workspace else { return }
        guard state != .submitting, state != .queued else { return }
        if state == .running,
           let lastSubmissionDate,
           now().timeIntervalSince(lastSubmissionDate) < rapidRunSuppressionInterval {
            return
        }
        let stateBeforeSubmission = state
        let command = workspace.runCommands.configuration.effectiveCommand
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            workspace.errorAlertMessage = RunError.emptyCommand.localizedDescription
            return
        }

        execute(command: command, stateOnFailure: stateBeforeSubmission)
    }

    func stop() {
        guard let workspace, let terminal else { return }
        guard state.isInterruptible else { return }

        if state == .queued, let queuedCommand {
            guard terminal.cancelQueuedCommand(queuedCommand) else {
                workspace.errorAlertMessage = RunError.commandSubmissionFailure.localizedDescription
                return
            }
            self.queuedCommand = nil
            state = .idle
        } else {
            guard terminal.sendInterrupt() else {
                workspace.errorAlertMessage = RunError.interruptFailure.localizedDescription
                return
            }
            state = .interruptSent
        }

        if workspace.runCommands.configuration.revealTerminalOnRun {
            workspace.isTerminalVisible = true
            terminal.setPanelVisible(true)
        }
        terminal.focusTerminal()
    }

    func resetStateForNewRun() {
        state = .idle
        queuedCommand = nil
        lastSubmissionDate = nil
    }

    private func execute(command: String, stateOnFailure: RunExecutionState) {
        guard let workspace, let terminal else {
            workspace?.errorAlertMessage = RunError.terminalUnavailable.localizedDescription
            return
        }

        state = .submitting
        let config = workspace.runCommands.configuration

        if config.revealTerminalOnRun {
            workspace.isTerminalVisible = true
            terminal.setPanelVisible(true)
        }

        if config.clearTerminalBeforeRun {
            terminal.clearDisplay()
        }
        terminal.focusTerminal()

        switch terminal.sendCommand(command) {
        case .submitted:
            state = .running
            lastSubmissionDate = now()
            AppLog.run.info("Run command dispatched to terminal session")
        case .queued:
            queuedCommand = command
            state = .queued
            AppLog.run.info("Run command queued for terminal startup")
        case .failed:
            state = stateOnFailure
            workspace.errorAlertMessage = RunError.commandSubmissionFailure.localizedDescription
        }
    }

    private func recordQueuedCommandDelivery(
        command: String,
        result: TerminalCommandSubmissionResult
    ) {
        guard command == queuedCommand else { return }
        queuedCommand = nil
        switch result {
        case .submitted:
            state = .running
            lastSubmissionDate = now()
        case .failed:
            state = .idle
            workspace?.errorAlertMessage = RunError.commandSubmissionFailure.localizedDescription
        case .queued:
            queuedCommand = command
            state = .queued
        }
    }
}
