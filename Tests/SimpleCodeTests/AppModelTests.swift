import AppKit
import Foundation
import Testing
@testable import SimpleCode

/// A real `XCUITest`/UI-automation pass could not be exercised in this sandboxed,
/// headless environment (see the implementation report's build/toolchain notes).
/// These tests exercise the exact model-layer state transitions that back the
/// three required launch/UI behaviors — welcome-on-launch, folder-open transitions
/// to the workspace state, and terminal panel show/hide — as the closest available
/// substitute, and remain valid regression coverage regardless of UI automation.
@Suite(.serialized)
@MainActor
struct AppModelTests {
    private func makeIsolatedAppModel() -> AppModel {
        let suiteName = "com.simplecode.tests.appmodel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppModel(
            recentWorkspaces: RecentWorkspaceStore(defaults: defaults),
            editorSettings: AppSettingsStore(defaults: defaults)
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SimpleCodeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func theWelcomeStateIsTheInitialRouteOnLaunch() {
        let appModel = makeIsolatedAppModel()

        #expect(!appModel.isWorkspaceOpen)
        switch appModel.route {
        case .welcome:
            break
        case .workspace:
            Issue.record("Expected the initial route to be .welcome")
        }
    }

    @Test func openingAFolderTransitionsToTheWorkspaceState() throws {
        let appModel = makeIsolatedAppModel()
        let folder = try makeTemporaryDirectory()

        appModel.openWorkspace(at: folder)

        #expect(appModel.isWorkspaceOpen)
        switch appModel.route {
        case .workspace(let workspace):
            #expect(workspace.rootURL.standardizedFileURL.path == folder.standardizedFileURL.path)
        case .welcome:
            Issue.record("Expected the route to be .workspace after opening a folder")
        }
    }

    @Test func closingTheWorkspaceReturnsToWelcome() throws {
        let appModel = makeIsolatedAppModel()
        appModel.openWorkspace(at: try makeTemporaryDirectory())

        appModel.closeWorkspace()

        #expect(!appModel.isWorkspaceOpen)
    }

    @Test func theTerminalPanelCanBeShownAndHidden() throws {
        let appModel = makeIsolatedAppModel()
        appModel.openWorkspace(at: try makeTemporaryDirectory())

        guard case .workspace(let workspace) = appModel.route else {
            Issue.record("Expected a workspace to be open")
            return
        }

        #expect(!workspace.isTerminalVisible)
        workspace.toggleTerminal()
        #expect(workspace.isTerminalVisible)
        workspace.toggleTerminal()
        #expect(!workspace.isTerminalVisible)
    }

    @Test func terminalHeightIsClampedToTheConfiguredRange() throws {
        let appModel = makeIsolatedAppModel()
        appModel.openWorkspace(at: try makeTemporaryDirectory())
        guard case .workspace(let workspace) = appModel.route else {
            Issue.record("Expected a workspace to be open")
            return
        }

        workspace.terminalHeight = 10
        #expect(workspace.terminalHeight == WorkspaceModel.minimumTerminalHeight)

        workspace.terminalHeight = 10_000
        #expect(workspace.terminalHeight == WorkspaceModel.maximumTerminalHeight)
    }

    @Test func floatingPanelDimensionsUseSpecifiedDefaultsAndClampRanges() throws {
        let appModel = makeIsolatedAppModel()
        appModel.openWorkspace(at: try makeTemporaryDirectory())
        guard case .workspace(let workspace) = appModel.route else {
            Issue.record("Expected a workspace to be open")
            return
        }

        #expect(workspace.sidebarWidth == 280)
        #expect(workspace.terminalHeight == 220)

        workspace.sidebarWidth = 10
        #expect(workspace.sidebarWidth == 240)
        workspace.sidebarWidth = 10_000
        #expect(workspace.sidebarWidth == 360)

        workspace.terminalHeight = 10
        #expect(workspace.terminalHeight == 120)
        workspace.terminalHeight = 10_000
        #expect(workspace.terminalHeight == 560)
    }

    @Test func workspacePanelLayoutFitsTerminalToSwiftUIAvailableHeight() {
        #expect(WorkspacePanelLayout.fittedTerminalHeight(configuredHeight: 220, availableHeight: 180) == 180)
        #expect(WorkspacePanelLayout.fittedTerminalHeight(configuredHeight: 220, availableHeight: -1) == 0)
    }

    @Test func workspacePanelLayoutReservesEditorSpaceForVisibleSidebar() {
        #expect(WorkspacePanelLayout.sidebarReservation(
            sidebarWidth: 280,
            panelInset: 12,
            isVisible: true
        ) == 304)
        #expect(WorkspacePanelLayout.sidebarReservation(
            sidebarWidth: 280,
            panelInset: 12,
            isVisible: false
        ) == 0)
    }

    @Test func workspacePanelLayoutUsesFullDistanceOffsets() {
        #expect(WorkspacePanelLayout.sidebarOffset(
            sidebarWidth: 280,
            panelInset: 12,
            isVisible: false
        ) == -304)
        #expect(WorkspacePanelLayout.sidebarOffset(
            sidebarWidth: 280,
            panelInset: 12,
            isVisible: true
        ) == 0)
        #expect(WorkspacePanelLayout.terminalOffset(
            terminalHeight: 220,
            panelInset: 12,
            isVisible: false
        ) == 232)
        #expect(WorkspacePanelLayout.terminalOffset(
            terminalHeight: 220,
            panelInset: 12,
            isVisible: true
        ) == 0)
    }

    @Test func workspacePanelLayoutUsesSharedMotionDuration() {
        #expect(WorkspacePanelLayout.motionDuration == 0.20)
    }

    @Test func nativeResizeHandleReportsWindowRelativeDragDistance() throws {
        defer { NSCursor.arrow.set() }
        let view = ResizeTrackingView()
        view.frame = NSRect(x: 0, y: 0, width: 14, height: 100)
        var horizontalDeltas: [CGFloat] = []
        view.axis = .horizontal
        view.onDrag = { horizontalDeltas.append($0) }
        view.mouseDown(with: try mouseEvent(.leftMouseDown, location: NSPoint(x: 20, y: 30)))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, location: NSPoint(x: 61, y: 74)))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, location: NSPoint(x: 70, y: 80)))
        #expect(horizontalDeltas == [41, 9])

        var verticalDelta: CGFloat?
        view.axis = .vertical
        view.onDrag = { verticalDelta = $0 }
        view.mouseDown(with: try mouseEvent(.leftMouseDown, location: NSPoint(x: 40, y: 50)))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, location: NSPoint(x: 28, y: 87)))
        #expect(verticalDelta == 37)

        NSCursor.arrow.set()
        view.cursorUpdate(with: try mouseEvent(.mouseMoved, location: NSPoint(x: 28, y: 87)))
        #expect(NSCursor.current == .resizeUpDown)

        let actionCursorRegion = CursorTrackingView(cursor: .pointingHand)
        NSCursor.arrow.set()
        actionCursorRegion.cursorUpdate(with: try mouseEvent(.mouseMoved, location: NSPoint(x: 4, y: 4)))
        #expect(NSCursor.current == .pointingHand)

        view.mouseDown(with: try mouseEvent(.leftMouseDown, location: NSPoint(x: 7, y: 50)))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, location: NSPoint(x: 40, y: 50)))
        view.mouseUp(with: try mouseEvent(.leftMouseUp, location: NSPoint(x: 40, y: 50)))
        #expect(NSCursor.current == .arrow)
    }

    @Test func workspaceBootstrapIsIdempotentAndTeardownIsSafeToRepeat() async throws {
        let suiteName = "com.simplecode.tests.bootstrap.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = try makeTemporaryDirectory()
        let workspace = WorkspaceModel(
            id: UUID(),
            rootURL: root,
            appSettings: AppSettingsStore(defaults: defaults),
            workspaceStateStore: WorkspaceStateStore(defaults: defaults, storageKey: "bootstrap.\(UUID().uuidString)")
        )

        await workspace.bootstrapAfterOpen()
        await workspace.bootstrapAfterOpen()

        #expect(workspace.hasBootstrapped)
        workspace.tearDown()
        workspace.tearDown()
        #expect(workspace.isTornDown)
    }

    private func mouseEvent(_ type: NSEvent.EventType, location: NSPoint) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }

    @Test func workspaceTeardownReleasesOpenDocumentsBeforeTermination() throws {
        let suiteName = "com.simplecode.tests.termination.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let workspace = WorkspaceModel(
            id: UUID(),
            rootURL: try makeTemporaryDirectory(),
            appSettings: AppSettingsStore(defaults: defaults),
            workspaceStateStore: WorkspaceStateStore(defaults: defaults, storageKey: "termination.\(UUID().uuidString)")
        )
        workspace.openDocuments.openSample(text: "let unsaved = true", displayName: "Unsaved.swift")

        workspace.tearDown()

        #expect(workspace.openDocuments.sessions.isEmpty)
        #expect(workspace.openDocuments.activeSessionID == nil)
    }
}
