import Foundation

struct RunConfiguration: Codable, Equatable, Sendable {
    var command: String
    var isCommandExplicit: Bool
    var suggestedCommand: String?
    var revealTerminalOnRun: Bool
    var clearTerminalBeforeRun: Bool

    static let `default` = RunConfiguration(
        command: "",
        isCommandExplicit: false,
        suggestedCommand: nil,
        revealTerminalOnRun: true,
        clearTerminalBeforeRun: false
    )

    var effectiveCommand: String {
        if isCommandExplicit {
            return command
        }
        if !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return command
        }
        return suggestedCommand ?? ""
    }

    var hasRunnableCommand: Bool {
        !effectiveCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
