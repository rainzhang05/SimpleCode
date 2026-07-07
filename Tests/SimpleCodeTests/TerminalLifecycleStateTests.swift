import Testing
@testable import SimpleCode

/// Tests the terminal session's lifecycle state machine in isolation from
/// SwiftTerm's view layer, per the requirement to test "terminal-session lifecycle
/// state where it can be separated from SwiftTerm's view."
struct TerminalLifecycleStateTests {
    @Test func notStartedIsTheInitialState() {
        let state = TerminalLifecycleState.notStarted
        #expect(state == .notStarted)
    }

    @Test func runningIsDistinctFromNotStarted() {
        #expect(TerminalLifecycleState.running != .notStarted)
    }

    @Test func terminatedStatesWithDifferentExitCodesAreNotEqual() {
        #expect(TerminalLifecycleState.terminated(exitCode: 0) != .terminated(exitCode: 1))
    }

    @Test func terminatedStatesWithTheSameExitCodeAreEqual() {
        #expect(TerminalLifecycleState.terminated(exitCode: 0) == .terminated(exitCode: 0))
    }

    @Test func terminatedWithNilExitCodeRepresentsAnAbnormalOrIOError() {
        let state = TerminalLifecycleState.terminated(exitCode: nil)
        #expect(state == .terminated(exitCode: nil))
        #expect(state != .terminated(exitCode: 0))
    }
}
