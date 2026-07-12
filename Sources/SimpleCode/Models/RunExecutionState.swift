import Foundation

/// Conservative run execution state. Run commands are written into the persistent
/// interactive shell, so SimpleCode knows a command was dispatched but does not own
/// a per-command process or reliable completion event.
///
/// Recovery to `.idle` happens when a new Run starts, the terminal restarts, the
/// shell terminates, or the workspace closes.
enum RunExecutionState: Equatable, Sendable {
    case idle
    case submitting
    case queued
    case running
    case interruptSent

    var isInterruptible: Bool {
        switch self {
        case .queued, .running: true
        case .idle, .submitting, .interruptSent: false
        }
    }

    var acceptsRunSubmission: Bool {
        switch self {
        case .idle, .running, .interruptSent: true
        case .submitting, .queued: false
        }
    }
}
