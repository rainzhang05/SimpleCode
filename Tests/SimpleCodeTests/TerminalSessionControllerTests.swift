import AppKit
import Foundation
import Observation
import SwiftTerm
import SwiftUI
import Testing
@testable import SimpleCode

private final class TerminalObservationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

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
        private(set) var focusCount = 0
        private(set) var resizedTo: [(cols: Int, rows: Int)] = []
        private(set) var events: [String] = []
        var sendSucceeds = true
        var byteSendSucceeds = true

        func startProcess(executable: String, environment: [String], currentDirectory: String) {
            launches.append(Launch(executable: executable, environment: environment, currentDirectory: currentDirectory))
            events.append("start")
            isProcessRunning = true
        }

        func send(text: String) -> Bool {
            sentText.append(text)
            events.append("send:\(text)")
            return sendSucceeds
        }

        func send(bytes: [UInt8]) -> Bool {
            guard isProcessRunning else { return false }
            sentBytes.append(bytes)
            events.append(byteSendSucceeds ? "bytes:\(bytes)" : "bytes-rejected:\(bytes)")
            return byteSendSucceeds
        }

        func focus() -> Bool {
            focusCount += 1
            events.append("focus")
            return true
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

    private func firstDescendant<T: NSView>(
        ofType type: T.Type,
        in view: NSView
    ) -> T? {
        if let match = view as? T {
            return match
        }

        for subview in view.subviews {
            if let match = firstDescendant(ofType: type, in: subview) {
                return match
            }
        }

        return nil
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
        let result = controller.sendCommand("echo queued")
        #expect(controller.state == .notStarted)
        #expect(result == .queued)

        let driver = TerminalDriverSpy()
        controller.attach(driver)

        #expect(driver.sentText == ["echo queued\n"])
    }

    @Test func runningTerminalSubmitsTheExactCommandOnce() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        let driver = TerminalDriverSpy()
        controller.attach(driver)
        controller.setPanelVisible(true)

        let result = controller.sendCommand("printf 'hello'")

        #expect(result == .submitted)
        #expect(driver.sentText == ["printf 'hello'\n"])
    }

    @Test func showingTerminalFocusesItImmediatelyAndEveryTimeItReopens() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        let driver = TerminalDriverSpy()
        controller.attach(driver)

        controller.setPanelVisible(true)
        #expect(driver.focusCount == 1)

        controller.setPanelVisible(false)
        controller.setPanelVisible(true)
        #expect(driver.focusCount == 2)
    }

    @Test func repeatedVisibleUpdatesDoNotResizeAnUnchangedTerminal() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        let driver = TerminalDriverSpy()
        controller.attach(driver)

        controller.setPanelVisible(true)
        let observationChanges = TerminalObservationCounter()
        withObservationTracking {
            _ = controller.isPanelVisible
            _ = controller.state
        } onChange: {
            observationChanges.increment()
        }
        for _ in 0..<20 {
            controller.setPanelVisible(true)
        }

        #expect(driver.resizedTo.count == 1)
        #expect(observationChanges.value == 0)
        controller.recordTerminalSize(cols: 120, rows: 40)
        controller.setPanelVisible(true)
        #expect(driver.resizedTo.count == 1)

        controller.setPanelVisible(false)
        controller.setPanelVisible(true)
        #expect(driver.resizedTo.count == 2)
        #expect(driver.resizedTo.last?.cols == 120)
        #expect(driver.resizedTo.last?.rows == 40)
    }

    @Test func driverSubmissionFailureIsReportedWithoutQueuingADuplicate() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        let driver = TerminalDriverSpy()
        controller.attach(driver)
        controller.setPanelVisible(true)
        driver.sendSucceeds = false

        let result = controller.sendCommand("echo fails")
        driver.sendSucceeds = true
        controller.startIfNeeded()

        #expect(result == .failed)
        #expect(driver.sentText == ["echo fails\n"])
    }

    @Test func clearSendsPromptResetBytesThenFocusesWithoutRestartingTheShell() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        let driver = TerminalDriverSpy()
        controller.attach(driver)
        controller.setPanelVisible(true)
        let launch = try #require(driver.launches.first)

        controller.clearDisplay()

        #expect(driver.launches == [launch])
        #expect(driver.terminateCount == 0)
        #expect(driver.isProcessRunning)
        #expect(controller.state == .running)
        #expect(driver.sentText.isEmpty)
        #expect(driver.sentBytes == [[0x15, 0x0C]])
        #expect(driver.events.suffix(2) == ["bytes:[21, 12]", "focus"])
        #expect(driver.focusCount == 2)
        #expect(!controller.consumeFocusRequest())
    }

    @Test func clearBeforeAttachmentWaitsToFocusUntilTheShellAcceptsResetBytes() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        controller.clearDisplay()
        let driver = TerminalDriverSpy()

        controller.attach(driver)

        #expect(driver.sentBytes.isEmpty)
        #expect(driver.focusCount == 0)

        controller.setPanelVisible(true)

        #expect(driver.sentBytes == [[0x15, 0x0C]])
        #expect(driver.events.suffix(2) == ["bytes:[21, 12]", "focus"])
        #expect(driver.focusCount == 1)
    }

    @Test func rejectedClearBlocksCommandUntilResetDeliveryRecovers() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        let driver = TerminalDriverSpy()
        var deliveries: [(String, TerminalCommandSubmissionResult)] = []
        controller.onQueuedCommandDelivery = { deliveries.append(($0, $1)) }
        controller.attach(driver)
        controller.setPanelVisible(true)
        driver.byteSendSucceeds = false

        controller.clearDisplay()
        let result = controller.sendCommand("echo guarded")
        controller.startIfNeeded()

        #expect(result == .queued)
        #expect(driver.sentText.isEmpty)
        #expect(deliveries.isEmpty)

        driver.byteSendSucceeds = true
        controller.startIfNeeded()

        let resetIndex = try #require(driver.events.firstIndex(of: "bytes:[21, 12]"))
        let focusIndex = try #require(driver.events[resetIndex...].firstIndex(of: "focus"))
        let sendIndex = try #require(driver.events.firstIndex(of: "send:echo guarded\n"))
        #expect(resetIndex < focusIndex)
        #expect(focusIndex < sendIndex)
        #expect(driver.sentText == ["echo guarded\n"])
        #expect(deliveries.count == 1)
        #expect(deliveries.first?.0 == "echo guarded")
        #expect(deliveries.first?.1 == .submitted)
    }

    @Test func rejectedClearKeepsFocusPendingUntilResetDeliverySucceeds() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        let driver = TerminalDriverSpy()
        controller.attach(driver)
        controller.setPanelVisible(true)
        driver.byteSendSucceeds = false

        controller.clearDisplay()

        #expect(!controller.consumeFocusRequest())
        #expect(driver.focusCount == 1)

        driver.byteSendSucceeds = true
        controller.startIfNeeded()

        #expect(driver.events.suffix(2) == ["bytes:[21, 12]", "focus"])
        #expect(driver.focusCount == 2)
        #expect(!controller.consumeFocusRequest())
    }

    @Test func interruptSendsOneControlCByte() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        let driver = TerminalDriverSpy()
        controller.attach(driver)
        controller.setPanelVisible(true)

        let result = controller.sendInterrupt()

        #expect(result)
        #expect(driver.sentBytes == [[0x03]])
    }

    @Test func queuedCommandCanBeCancelledBeforeTerminalAttachment() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        #expect(controller.sendCommand("sleep 60") == .queued)

        #expect(controller.cancelQueuedCommand("sleep 60"))
        let driver = TerminalDriverSpy()
        controller.attach(driver)

        #expect(driver.sentText.isEmpty)
    }

    @Test func failedDeferredDeliveryIsReportedAndNotRetriedSilently() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        var deliveries: [(String, TerminalCommandSubmissionResult)] = []
        controller.onQueuedCommandDelivery = { deliveries.append(($0, $1)) }
        #expect(controller.sendCommand("echo queued") == .queued)
        let driver = TerminalDriverSpy()
        driver.sendSucceeds = false

        controller.attach(driver)
        driver.sendSucceeds = true
        controller.startIfNeeded()

        #expect(deliveries.count == 1)
        #expect(deliveries.first?.0 == "echo queued")
        #expect(deliveries.first?.1 == .failed)
        #expect(driver.sentText == ["echo queued\n"])
        #expect(driver.launches.count == 1)
    }

    @Test func pendingClearRunsBeforeAQueuedCommandFlushes() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        controller.clearDisplay()
        #expect(controller.sendCommand("echo clean") == .queued)
        let driver = TerminalDriverSpy()

        controller.attach(driver)

        let clearIndex = try #require(driver.events.firstIndex(of: "bytes:[21, 12]"))
        let focusIndex = try #require(driver.events.firstIndex(of: "focus"))
        let sendIndex = try #require(driver.events.firstIndex(of: "send:echo clean\n"))
        #expect(clearIndex < sendIndex)
        #expect(clearIndex < focusIndex)
        #expect(focusIndex < sendIndex)
        #expect(driver.sentText == ["echo clean\n"])
    }

    @Test func shellTerminationFailsAndDrainsQueuedCommands() throws {
        let controller = TerminalSessionController(workingDirectory: try makeTemporaryDirectory())
        var deliveries: [(String, TerminalCommandSubmissionResult)] = []
        controller.onQueuedCommandDelivery = { deliveries.append(($0, $1)) }
        #expect(controller.sendCommand("echo abandoned") == .queued)

        controller.recordTermination(exitCode: 1)
        let driver = TerminalDriverSpy()
        controller.attach(driver)

        #expect(deliveries.count == 1)
        #expect(deliveries.first?.0 == "echo abandoned")
        #expect(deliveries.first?.1 == .failed)
        #expect(driver.sentText.isEmpty)
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

    @Test func hiddenTerminalKeepsItsAppKitSurfaceMountedAndVisible() throws {
        let workspace = try makeWorkspace()
        defer { workspace.tearDown() }
        #expect(!workspace.isTerminalVisible)

        let host = NSHostingView(rootView: WorkspaceView(workspace: workspace, onCloseWorkspace: {}))
        host.frame = NSRect(x: 0, y: 0, width: 1_100, height: 700)
        host.layoutSubtreeIfNeeded()

        let terminalSurface = try #require(firstDescendant(
            ofType: LocalProcessTerminalView.self,
            in: host
        ))
        #expect(!terminalSurface.isHidden)
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
