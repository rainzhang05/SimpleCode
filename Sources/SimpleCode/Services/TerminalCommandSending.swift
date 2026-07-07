import Foundation

/// Protocol for submitting commands to the persistent terminal session.
/// Implemented by `TerminalSessionController`; mocked in unit tests.
@MainActor
protocol TerminalCommandSending: AnyObject {
    var state: TerminalLifecycleState { get }
    var isPanelVisible: Bool { get set }

    func startIfNeeded()
    func sendCommand(_ command: String)
    func sendInterrupt()
    func clearDisplay()
    func focusTerminal()
    func setPanelVisible(_ visible: Bool)
}
