import Foundation

enum TerminalCommandSubmissionResult: Equatable, Sendable {
    case submitted
    case queued
    case failed
}

/// Protocol for submitting commands to the persistent terminal session.
/// Implemented by `TerminalSessionController`; mocked in unit tests.
@MainActor
protocol TerminalCommandSending: AnyObject {
    var state: TerminalLifecycleState { get }
    var isPanelVisible: Bool { get set }
    var onQueuedCommandDelivery: ((String, TerminalCommandSubmissionResult) -> Void)? { get set }

    func startIfNeeded()
    @discardableResult
    func sendCommand(_ command: String) -> TerminalCommandSubmissionResult
    @discardableResult
    func sendInterrupt() -> Bool
    @discardableResult
    func cancelQueuedCommand(_ command: String) -> Bool
    func clearDisplay()
    func focusTerminal()
    func setPanelVisible(_ visible: Bool)
}
