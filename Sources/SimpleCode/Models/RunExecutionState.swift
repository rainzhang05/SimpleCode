import Foundation

/// Conservative run execution state. Run commands are written into the persistent
/// interactive shell, so SimpleCode knows a command was dispatched but does not own
/// a per-command process or reliable completion event.
///
/// Recovery to `.idle`:
/// Recovery to `.idle` happens when a new Run starts, the terminal restarts, the
/// shell terminates, or the workspace closes. `.possiblyRunning` is intentionally
/// not interruptible in app chrome; users can still send Ctrl-C directly to the
/// focused terminal.
enum RunExecutionState: Equatable, Sendable {
    case idle
    case submitting
    case possiblyRunning
    case interruptSent

    var isInterruptible: Bool {
        switch self {
        case .idle, .possiblyRunning: false
        case .submitting, .interruptSent: true
        }
    }
}
