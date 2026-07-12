import Foundation
import Testing
@testable import SimpleCode

@MainActor
final class MockTerminalCommandSender: TerminalCommandSending {
    var state: TerminalLifecycleState = .notStarted
    var isPanelVisible = false
    var onQueuedCommandDelivery: ((String, TerminalCommandSubmissionResult) -> Void)?
    var sentCommands: [String] = []
    var queuedCommands: [String] = []
    var interruptCount = 0
    var clearCount = 0
    var focusCount = 0
    var startCount = 0
    var startSucceeds = true
    var delayReadiness = false
    var submissionResult: TerminalCommandSubmissionResult = .submitted
    var interruptSucceeds = true
    var events: [String] = []
    weak var attachedView: MockTerminalView?

    func startIfNeeded() {
        startCount += 1
        events.append("start")
        guard startSucceeds else { return }
        if !delayReadiness {
            state = .running
        }
    }

    func sendCommand(_ command: String) -> TerminalCommandSubmissionResult {
        sentCommands.append(command)
        events.append("send:\(command)")
        if submissionResult == .queued {
            queuedCommands.append(command)
        }
        return submissionResult
    }

    func sendInterrupt() -> Bool {
        interruptCount += 1
        events.append("interrupt")
        return interruptSucceeds
    }
    func cancelQueuedCommand(_ command: String) -> Bool {
        guard let index = queuedCommands.firstIndex(of: command) else { return false }
        queuedCommands.remove(at: index)
        events.append("cancel:\(command)")
        return true
    }
    func clearDisplay() { clearCount += 1; events.append("clear") }
    func focusTerminal() { focusCount += 1; events.append("focus") }
    func setPanelVisible(_ visible: Bool) {
        isPanelVisible = visible
        events.append("visible:\(visible)")
    }

    func completeQueuedCommand(_ command: String, result: TerminalCommandSubmissionResult) {
        if let index = queuedCommands.firstIndex(of: command) {
            queuedCommands.remove(at: index)
        }
        onQueuedCommandDelivery?(command, result)
    }
}

final class MockTerminalView {}

@Suite(.serialized)
@MainActor
struct RunExecutionControllerTests {
    private func makeWorkspace() throws -> (WorkspaceModel, MockTerminalCommandSender) {
        let suiteName = "com.simplecode.tests.run.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = WorkspaceStateStore(defaults: defaults, storageKey: "r.\(UUID())")
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let workspace = WorkspaceModel(
            id: UUID(),
            rootURL: root,
            appSettings: AppSettingsStore(defaults: defaults),
            workspaceStateStore: store
        )
        let terminal = MockTerminalCommandSender()
        workspace.runExecution.bind(workspace: workspace, terminal: terminal)
        return (workspace, terminal)
    }

    @Test func emptyCommandRejected() throws {
        let (workspace, _) = try makeWorkspace()
        workspace.runCommands.clearExplicitCommand()
        workspace.runExecution.run()
        #expect(workspace.errorAlertMessage != nil)
    }

    @Test func runRevealsThenSubmitsTheExactCommandOnce() throws {
        let (workspace, terminal) = try makeWorkspace()
        workspace.runCommands.setCommand("printf 'x'", explicit: true)

        workspace.runExecution.run()

        #expect(terminal.sentCommands == ["printf 'x'"])
        #expect(terminal.events.first == "visible:true")
        #expect(workspace.runExecution.state == .running)
        #expect(workspace.isTerminalVisible)
    }

    @Test func queuedSubmissionBecomesInterruptibleWithoutResubmission() throws {
        let (workspace, terminal) = try makeWorkspace()
        terminal.submissionResult = .queued
        workspace.runCommands.setCommand("sleep 1", explicit: true)

        workspace.runExecution.run()

        #expect(terminal.sentCommands == ["sleep 1"])
        #expect(workspace.runExecution.state == .queued)
        #expect(workspace.runExecution.state.isInterruptible)
    }

    @Test func failedDeferredDeliveryReturnsTheRunToIdleWithAnError() throws {
        let (workspace, terminal) = try makeWorkspace()
        terminal.submissionResult = .queued
        workspace.runCommands.setCommand("echo later", explicit: true)
        workspace.runExecution.run()

        terminal.completeQueuedCommand("echo later", result: .failed)

        #expect(workspace.runExecution.state == .idle)
        #expect(workspace.errorAlertMessage == RunError.commandSubmissionFailure.localizedDescription)
    }

    @Test func failedSubmissionReturnsIdleWithAnActionableError() throws {
        let (workspace, terminal) = try makeWorkspace()
        terminal.submissionResult = .failed
        workspace.runCommands.setCommand("false", explicit: true)

        workspace.runExecution.run()

        #expect(terminal.sentCommands == ["false"])
        #expect(workspace.runExecution.state == .idle)
        #expect(workspace.errorAlertMessage == RunError.commandSubmissionFailure.localizedDescription)
    }

    @Test func laterRunCanSubmitAgainAfterTheRapidDuplicateWindow() throws {
        let (workspace, terminal) = try makeWorkspace()
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let controller = RunExecutionController(now: { currentDate })
        controller.bind(workspace: workspace, terminal: terminal)
        workspace.runCommands.setCommand("echo first", explicit: true)
        controller.run()

        currentDate.addTimeInterval(1)
        workspace.runCommands.setCommand("echo second", explicit: true)
        controller.run()

        #expect(terminal.sentCommands == ["echo first", "echo second"])
        #expect(controller.state == .running)
    }

    @Test func failedLaterRunPreservesTheEarlierInterruptibleState() throws {
        let (workspace, terminal) = try makeWorkspace()
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let controller = RunExecutionController(now: { currentDate })
        controller.bind(workspace: workspace, terminal: terminal)
        workspace.runCommands.setCommand("sleep 60", explicit: true)
        controller.run()

        currentDate.addTimeInterval(1)
        terminal.submissionResult = .failed
        workspace.runCommands.setCommand("echo rejected", explicit: true)
        controller.run()

        #expect(controller.state == .running)
        #expect(controller.state.isInterruptible)
        #expect(workspace.errorAlertMessage == RunError.commandSubmissionFailure.localizedDescription)
    }

    @Test func emptyLaterRunDoesNotLoseTheEarlierInterruptibleState() throws {
        let (workspace, terminal) = try makeWorkspace()
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let controller = RunExecutionController(now: { currentDate })
        controller.bind(workspace: workspace, terminal: terminal)
        workspace.runCommands.setCommand("sleep 60", explicit: true)
        controller.run()

        currentDate.addTimeInterval(1)
        workspace.runCommands.setCommand("   ", explicit: true)
        controller.run()

        #expect(controller.state == .running)
        #expect(controller.state.isInterruptible)
        #expect(workspace.errorAlertMessage == RunError.emptyCommand.localizedDescription)
    }

    @Test func shellTerminationResetsState() throws {
        let (workspace, _) = try makeWorkspace()
        workspace.runCommands.setCommand("sleep 1", explicit: true)
        workspace.runExecution.run()
        #expect(workspace.runExecution.state == .running)
        workspace.terminal.onShellTerminated?()
        #expect(workspace.runExecution.state == .idle)
    }

    @Test func terminalRestartResetsRunStateWithoutWaitingForAShellCallback() throws {
        let (workspace, _) = try makeWorkspace()
        workspace.runCommands.setCommand("sleep 1", explicit: true)
        workspace.runExecution.run()
        #expect(workspace.runExecution.state == .running)

        workspace.terminal.restart()

        #expect(workspace.runExecution.state == .idle)
    }
}

@Suite(.serialized)
@MainActor
struct TerminalCommandQueueTests {
    private func makeWorkspace() throws -> (WorkspaceModel, MockTerminalCommandSender) {
        let suiteName = "com.simplecode.tests.queue.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = WorkspaceStateStore(defaults: defaults, storageKey: "queue.\(UUID())")
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let workspace = WorkspaceModel(
            id: UUID(),
            rootURL: root,
            appSettings: AppSettingsStore(defaults: defaults),
            workspaceStateStore: store
        )
        let terminal = MockTerminalCommandSender()
        workspace.runExecution.bind(workspace: workspace, terminal: terminal)
        return (workspace, terminal)
    }

    @Test func activeRunSendsControlCAndFocusesTheTerminal() throws {
        let (workspace, terminal) = try makeWorkspace()
        workspace.runCommands.setCommand("sleep 60", explicit: true)
        workspace.runExecution.run()
        workspace.runExecution.stop()

        #expect(terminal.interruptCount == 1)
        #expect(workspace.runExecution.state == .interruptSent)
        #expect(terminal.focusCount == 2)
        #expect(workspace.isTerminalVisible)
    }

    @Test func stopCancelsAQueuedRunWithoutSendingControlC() throws {
        let (workspace, terminal) = try makeWorkspace()
        terminal.submissionResult = .queued
        workspace.runCommands.setCommand("sleep 60", explicit: true)
        workspace.runExecution.run()

        workspace.runExecution.stop()

        #expect(terminal.queuedCommands.isEmpty)
        #expect(terminal.interruptCount == 0)
        #expect(workspace.runExecution.state == .idle)
    }

    @Test func failedInterruptKeepsTheRunActiveAndReportsTheError() throws {
        let (workspace, terminal) = try makeWorkspace()
        terminal.interruptSucceeds = false
        workspace.runCommands.setCommand("sleep 60", explicit: true)
        workspace.runExecution.run()

        workspace.runExecution.stop()

        #expect(terminal.interruptCount == 1)
        #expect(workspace.runExecution.state == .running)
        #expect(workspace.errorAlertMessage == RunError.interruptFailure.localizedDescription)
    }

    @Test func rapidDoubleRunSubmitsTheCommandExactlyOnce() throws {
        let (workspace, terminal) = try makeWorkspace()
        workspace.runCommands.setCommand("echo one", explicit: true)

        workspace.runExecution.run()
        workspace.runExecution.run()

        #expect(terminal.sentCommands == ["echo one"])
        #expect(workspace.runExecution.state == .running)
    }

    @Test func clearBeforeRunUsesTheEmulatorBeforeCommandSubmission() throws {
        let (workspace, terminal) = try makeWorkspace()
        workspace.runCommands.setCommand("echo clean", explicit: true)
        workspace.runCommands.setClearTerminalBeforeRun(true)

        workspace.runExecution.run()

        let clearIndex = try #require(terminal.events.firstIndex(of: "clear"))
        let sendIndex = try #require(terminal.events.firstIndex(of: "send:echo clean"))
        #expect(clearIndex < sendIndex)
        #expect(terminal.clearCount == 1)
    }

    @Test func workspaceTeardownResetsRunState() throws {
        let (workspace, _) = try makeWorkspace()
        workspace.runCommands.setCommand("sleep 60", explicit: true)
        workspace.runExecution.run()
        workspace.tearDown()
        #expect(workspace.runExecution.state == .idle)
    }
}
