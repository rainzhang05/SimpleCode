import Foundation

struct RunCommandSuggestion: Sendable, Equatable {
    enum Confidence: Sendable, Equatable {
        case high
        case medium
        case guidance
    }

    let command: String?
    let reason: String
    let confidence: Confidence

    var isRunnable: Bool {
        guard let command else { return false }
        return !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
