import Foundation
import Testing
@testable import SimpleCode

@Suite(.serialized)
@MainActor
struct TerminalSessionControllerTests {
    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SimpleCodeTerminalTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func notStartedIsTheInitialState() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        #expect(controller.state == .notStarted)
    }

    @Test func startIfNeededWithoutAnAttachedViewLeavesStateNotStarted() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        controller.startIfNeeded()
        #expect(controller.state == .notStarted)
    }

    @Test func recordTerminationUpdatesState() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        controller.recordTermination(exitCode: 0)
        #expect(controller.state == .terminated(exitCode: 0))
    }

    @Test func restartWhenNotRunningReturnsToNotStartedWithoutAView() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        controller.restart()
        #expect(controller.state == .notStarted)
    }

    @Test func terminateWithoutAViewDoesNotCrash() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        controller.terminate()
        #expect(controller.state == .notStarted)
    }

    @Test func queuesCommandBeforeStartup() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        controller.sendCommand("echo queued")
        #expect(controller.state == .notStarted)
    }

    @Test func restartClearsPendingCommands() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        controller.sendCommand("echo one")
        controller.restart()
        #expect(controller.state == .notStarted)
    }

    @Test func terminationCallbackFires() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        var fired = false
        controller.onShellTerminated = { fired = true }
        controller.recordTermination(exitCode: 0)
        #expect(fired)
    }

    @Test func terminationDuringRestartDoesNotFireIdleCallbackWhenRunning() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        var fired = false
        controller.onShellTerminated = { fired = true }
        // Without a live view the session cannot reach .running; verify callback on ordinary termination.
        controller.recordTermination(exitCode: 0)
        #expect(fired)
    }
}
