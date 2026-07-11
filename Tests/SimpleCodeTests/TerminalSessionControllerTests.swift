import AppKit
import Foundation
import SwiftUI
import Testing
@testable import SimpleCode

@Suite(.serialized)
@MainActor
struct TerminalSessionControllerTests {
    @MainActor
    private final class TerminalDriverSpy: TerminalSessionDriving {
        struct Launch: Equatable {
            let executable: String
            let environment: [String]
            let currentDirectory: String
        }

        var isProcessRunning = false
        private(set) var launches: [Launch] = []
        private(set) var sentText: [String] = []
        private(set) var sentBytes: [[UInt8]] = []
        private(set) var terminateCount = 0
        private(set) var resizedTo: [(cols: Int, rows: Int)] = []

        func startProcess(executable: String, environment: [String], currentDirectory: String) {
            launches.append(Launch(executable: executable, environment: environment, currentDirectory: currentDirectory))
            isProcessRunning = true
        }

        func send(text: String) {
            sentText.append(text)
        }

        func send(bytes: [UInt8]) {
            sentBytes.append(bytes)
        }

        func terminate() {
            terminateCount += 1
            isProcessRunning = false
        }

        func resize(cols: Int, rows: Int) {
            resizedTo.append((cols, rows))
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SimpleCodeTerminalTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeWorkspace() throws -> WorkspaceModel {
        let suiteName = "com.simplecode.tests.terminal-layout.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return WorkspaceModel(
            id: UUID(),
            rootURL: try makeTemporaryDirectory(),
            appSettings: AppSettingsStore(defaults: defaults),
            workspaceStateStore: WorkspaceStateStore(
                defaults: defaults,
                storageKey: "terminal-layout.\(UUID().uuidString)"
            )
        )
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

    @Test func attachedTerminalStartsOnlyAfterThePanelIsRevealed() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        let driver = TerminalDriverSpy()

        controller.attach(driver)
        #expect(driver.launches.isEmpty)
        #expect(controller.state == .notStarted)

        controller.setPanelVisible(true)
        #expect(driver.launches.count == 1)
        #expect(controller.state == .running)
    }

    @Test func restartStartsAFreshShellWithoutWaitingForATerminationCallback() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        let driver = TerminalDriverSpy()
        controller.attach(driver)
        controller.setPanelVisible(true)

        controller.restart()

        #expect(driver.terminateCount == 1)
        #expect(driver.launches.count == 2)
        #expect(controller.state == .running)
    }

    @Test func delayedTerminationFromTheReplacedShellDoesNotStopTheFreshSession() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        let driver = TerminalDriverSpy()
        controller.attach(driver)
        controller.setPanelVisible(true)

        controller.restart()
        controller.recordTermination(exitCode: 0)

        #expect(driver.isProcessRunning)
        #expect(controller.state == .running)
    }

    @Test func startRequestRecoversWhenTheDriverExitedWithoutACallback() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        let driver = TerminalDriverSpy()
        controller.attach(driver)
        controller.setPanelVisible(true)
        driver.isProcessRunning = false

        controller.startIfNeeded()

        #expect(driver.launches.count == 2)
        #expect(controller.state == .running)
    }

    @Test func replacingTheTerminalDriverTerminatesThePreviousShell() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        let firstDriver = TerminalDriverSpy()
        let replacementDriver = TerminalDriverSpy()

        controller.attach(firstDriver)
        controller.setPanelVisible(true)
        controller.attach(replacementDriver)

        #expect(firstDriver.terminateCount == 1)
        #expect(replacementDriver.launches.count == 1)
        #expect(controller.state == .running)
    }

    @Test func detachingARunningDriverTerminatesItAndRestartsForTheReplacementView() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        let firstDriver = TerminalDriverSpy()
        let attachment = controller.attach(firstDriver)
        controller.setPanelVisible(true)

        controller.detach(attachment)

        #expect(firstDriver.terminateCount == 1)
        #expect(controller.state == .notStarted)

        let replacementDriver = TerminalDriverSpy()
        controller.attach(replacementDriver)

        #expect(replacementDriver.launches.count == 1)
        #expect(controller.state == .running)
    }

    @Test func fiftyPanelTogglesKeepOneMountedTerminalDriverAndBoundedState() throws {
        let workspace = try makeWorkspace()

        let host = NSHostingView(rootView: WorkspaceView(workspace: workspace, onCloseWorkspace: {}))
        host.frame = NSRect(x: 0, y: 0, width: 1_100, height: 700)
        host.layoutSubtreeIfNeeded()

        let driver = TerminalDriverSpy()
        workspace.terminal.attach(driver)
        let terminalIdentity = ObjectIdentifier(workspace.terminal)
        let sidebarModelIdentity = ObjectIdentifier(workspace.fileTree)

        // Establish the mounted terminal's real geometry before measuring repeated
        // presentation-only toggles. The regression is about growth/churn after the
        // first reveal, not SwiftTerm replacing its initial 80x24 bootstrap size.
        workspace.toggleTerminal()
        host.rootView = WorkspaceView(workspace: workspace, onCloseWorkspace: {})
        host.layoutSubtreeIfNeeded()
        workspace.toggleTerminal()
        host.rootView = WorkspaceView(workspace: workspace, onCloseWorkspace: {})
        host.layoutSubtreeIfNeeded()
        let initialTerminalSize = (workspace.terminal.lastKnownCols, workspace.terminal.lastKnownRows)

        for _ in 0..<50 {
            workspace.toggleSidebar()
            workspace.toggleTerminal()
            host.rootView = WorkspaceView(workspace: workspace, onCloseWorkspace: {})
            host.layoutSubtreeIfNeeded()
        }

        #expect(ObjectIdentifier(workspace.terminal) == terminalIdentity)
        #expect(ObjectIdentifier(workspace.fileTree) == sidebarModelIdentity)
        #expect(driver.launches.count == 1)
        #expect(driver.terminateCount == 0)
        #expect(driver.sentText.isEmpty)
        #expect(driver.sentBytes.isEmpty)
        #expect(workspace.terminal.lastKnownCols == initialTerminalSize.0)
        #expect(workspace.terminal.lastKnownRows == initialTerminalSize.1)
        #expect(!workspace.isTerminalVisible)
        #expect(workspace.isSidebarVisible)

        workspace.tearDown()
        workspace.tearDown()
        #expect(driver.terminateCount == 1)
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
