import Foundation
import Testing
@testable import SimpleCode

@MainActor
final class MockTerminalCommandSender: TerminalCommandSending {
    var state: TerminalLifecycleState = .notStarted
    var isPanelVisible = false
    var sentCommands: [String] = []
    var interruptCount = 0
    var clearCount = 0
    var focusCount = 0
    var startCount = 0
    var startSucceeds = true
    var delayReadiness = false
    weak var attachedView: MockTerminalView?

    func startIfNeeded() {
        startCount += 1
        guard startSucceeds else { return }
        if !delayReadiness {
            state = .running
        }
    }

    func sendCommand(_ command: String) {
        if state == .running {
            sentCommands.append(command)
        }
    }

    func sendInterrupt() { interruptCount += 1 }
    func clearDisplay() { clearCount += 1 }
    func focusTerminal() { focusCount += 1 }
    func setPanelVisible(_ visible: Bool) { isPanelVisible = visible }
}

final class MockTerminalView {}

@Suite(.serialized)
@MainActor
struct RunExecutionControllerTests {
    private func makeWorkspace(provenance: WorkspaceOpenProvenance = .userCreated) throws -> WorkspaceModel {
        let suiteName = "com.simplecode.tests.run.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = WorkspaceStateStore(defaults: defaults, storageKey: "r.\(UUID())")
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return WorkspaceModel(
            id: UUID(),
            rootURL: root,
            appSettings: AppSettingsStore(defaults: defaults),
            workspaceStateStore: store,
            provenance: provenance
        )
    }

    @Test func emptyCommandRejected() throws {
        let workspace = try makeWorkspace()
        workspace.runCommands.clearExplicitCommand()
        workspace.runExecution.run()
        #expect(workspace.errorAlertMessage != nil)
    }

    @Test func untrustedShowsTrustSheet() throws {
        let workspace = try makeWorkspace(provenance: .openedExisting)
        workspace.runCommands.setCommand("printf 'x'\n", explicit: true)
        workspace.runExecution.run()
        #expect(workspace.runExecution.showTrustSheet)
    }

    @Test func runOnceDoesNotPersistTrust() throws {
        let suiteName = "com.simplecode.tests.once.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = WorkspaceStateStore(defaults: defaults, storageKey: "o.\(UUID())")
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let id = UUID()
        let workspace = WorkspaceModel(
            id: id,
            rootURL: root,
            appSettings: AppSettingsStore(defaults: defaults),
            workspaceStateStore: store,
            provenance: .openedExisting
        )
        workspace.runCommands.setCommand("printf 'x'\n", explicit: true)
        workspace.runExecution.pendingTrustCommand = "printf 'x'\n"
        workspace.runExecution.runOnceAfterTrustPrompt()
        #expect(!workspace.trust.isTrusted)
    }

    @Test func trustAndRunPersistsTrust() throws {
        let suiteName = "com.simplecode.tests.tar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = WorkspaceStateStore(defaults: defaults, storageKey: "tar.\(UUID())")
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let id = UUID()
        let workspace = WorkspaceModel(
            id: id,
            rootURL: root,
            appSettings: AppSettingsStore(defaults: defaults),
            workspaceStateStore: store,
            provenance: .openedExisting
        )
        workspace.runExecution.pendingTrustCommand = "printf 'x'\n"
        workspace.runExecution.trustAndRun()
        #expect(workspace.trust.isTrusted)
    }

    @Test func cancelTrustPromptSubmitsNothing() throws {
        let workspace = try makeWorkspace(provenance: .openedExisting)
        workspace.runCommands.setCommand("printf 'x'\n", explicit: true)
        workspace.runExecution.run()
        #expect(workspace.runExecution.showTrustSheet)
        workspace.runExecution.cancelTrustPrompt()
        #expect(workspace.runExecution.pendingTrustCommand == nil)
        #expect(!workspace.runExecution.showTrustSheet)
        #expect(workspace.runExecution.state == .idle)
    }

    @Test func shellTerminationResetsState() throws {
        let workspace = try makeWorkspace()
        workspace.runCommands.setCommand("sleep 1", explicit: true)
        workspace.runExecution.run()
        #expect(workspace.runExecution.state == .possiblyRunning)
        workspace.terminal.onShellTerminated?()
        #expect(workspace.runExecution.state == .idle)
    }

    @Test func terminalRestartResetsRunStateWithoutWaitingForAShellCallback() throws {
        let workspace = try makeWorkspace()
        workspace.runCommands.setCommand("sleep 1", explicit: true)
        workspace.runExecution.run()
        #expect(workspace.runExecution.state == .possiblyRunning)

        workspace.terminal.restart()

        #expect(workspace.runExecution.state == .idle)
    }
}

@Suite(.serialized)
@MainActor
struct TerminalCommandQueueTests {
    @Test func dispatchedPersistentShellCommandDoesNotExposeStaleStopState() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suiteName = "com.simplecode.tests.stop.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = WorkspaceStateStore(defaults: defaults, storageKey: "s.\(UUID())")
        let workspace = WorkspaceModel(
            id: UUID(),
            rootURL: root,
            appSettings: AppSettingsStore(defaults: defaults),
            workspaceStateStore: store,
            provenance: .userCreated
        )
        workspace.runCommands.setCommand("sleep 60", explicit: true)
        workspace.runExecution.run()
        #expect(workspace.runExecution.state == .possiblyRunning)
        #expect(!workspace.runExecution.state.isInterruptible)
        workspace.runExecution.stop()
        #expect(workspace.runExecution.state == .possiblyRunning)
    }

    @Test func rapidRunWhileSubmittingIgnored() throws {
        let workspace = try {
            let suiteName = "com.simplecode.tests.rapid.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let store = WorkspaceStateStore(defaults: defaults, storageKey: "rapid.\(UUID())")
            let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            return WorkspaceModel(
                id: UUID(),
                rootURL: root,
                appSettings: AppSettingsStore(defaults: defaults),
                workspaceStateStore: store,
                provenance: .userCreated
            )
        }()
        workspace.runCommands.setCommand("echo one", explicit: true)
        workspace.runExecution.run()
        let stateAfterFirst = workspace.runExecution.state
        workspace.runExecution.run()
        #expect(stateAfterFirst == .possiblyRunning)
        #expect(workspace.runExecution.state == .possiblyRunning)
    }

    @Test func workspaceTeardownResetsRunState() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suiteName = "com.simplecode.tests.td.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = WorkspaceStateStore(defaults: defaults, storageKey: "td.\(UUID())")
        let workspace = WorkspaceModel(
            id: UUID(),
            rootURL: root,
            appSettings: AppSettingsStore(defaults: defaults),
            workspaceStateStore: store,
            provenance: .userCreated
        )
        workspace.runCommands.setCommand("sleep 60", explicit: true)
        workspace.runExecution.run()
        workspace.tearDown()
        #expect(workspace.runExecution.state == .idle)
    }
}
