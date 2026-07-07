import Foundation

@MainActor
@Observable
final class RunCommandStore {
    private let workspaceID: UUID
    private let stateStore: WorkspaceStateStore
    private let suggestionService: RunCommandSuggestionService

    private(set) var configuration: RunConfiguration
    private(set) var latestSuggestion: RunCommandSuggestion?

    init(
        workspaceID: UUID,
        rootURL: URL,
        stateStore: WorkspaceStateStore,
        suggestionService: RunCommandSuggestionService = RunCommandSuggestionService()
    ) {
        self.workspaceID = workspaceID
        self.stateStore = stateStore
        self.suggestionService = suggestionService
        self.configuration = stateStore.state(for: workspaceID).runConfiguration
    }

    var hasRunnableCommand: Bool { configuration.hasRunnableCommand }

    func refreshSuggestion(rootURL: URL) async {
        let suggestion = await suggestionService.suggest(rootURL: rootURL)
        latestSuggestion = suggestion
        stateStore.updateRunConfiguration(for: workspaceID) { config in
            if let suggestion {
                config.suggestedCommand = suggestion.isRunnable ? suggestion.command : nil
                if !config.isCommandExplicit, let command = suggestion.command, suggestion.isRunnable {
                    config.command = command
                }
            } else {
                config.suggestedCommand = nil
            }
        }
        configuration = stateStore.state(for: workspaceID).runConfiguration
    }

    func setCommand(_ command: String, explicit: Bool) {
        stateStore.updateRunConfiguration(for: workspaceID) { config in
            config.command = command
            config.isCommandExplicit = explicit
            if command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                config.isCommandExplicit = false
            }
        }
        configuration = stateStore.state(for: workspaceID).runConfiguration
    }

    func useSuggestion() {
        guard let suggestion = latestSuggestion, suggestion.isRunnable, let command = suggestion.command else { return }
        setCommand(command, explicit: true)
    }

    func clearExplicitCommand() {
        stateStore.updateRunConfiguration(for: workspaceID) { config in
            config.command = ""
            config.isCommandExplicit = false
        }
        configuration = stateStore.state(for: workspaceID).runConfiguration
    }

    func setRevealTerminalOnRun(_ value: Bool) {
        stateStore.updateRunConfiguration(for: workspaceID) { $0.revealTerminalOnRun = value }
        configuration = stateStore.state(for: workspaceID).runConfiguration
    }

    func setClearTerminalBeforeRun(_ value: Bool) {
        stateStore.updateRunConfiguration(for: workspaceID) { $0.clearTerminalBeforeRun = value }
        configuration = stateStore.state(for: workspaceID).runConfiguration
    }

    func persistEdits(command: String, revealTerminal: Bool, clearTerminal: Bool) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        stateStore.updateRunConfiguration(for: workspaceID) { config in
            config.command = command
            config.isCommandExplicit = !trimmed.isEmpty
            config.revealTerminalOnRun = revealTerminal
            config.clearTerminalBeforeRun = clearTerminal
        }
        configuration = stateStore.state(for: workspaceID).runConfiguration
    }
}
