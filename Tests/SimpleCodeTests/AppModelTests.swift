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

    @Test func workspacePanelLayoutConsumesTheActualTopInsetWithoutNegativeGeometry() {
        #expect(WorkspacePanelLayout.contentHeight(containerHeight: 700, topInset: 52) == 648)
        #expect(WorkspacePanelLayout.contentHeight(containerHeight: 700, topInset: -10) == 700)
        #expect(WorkspacePanelLayout.contentHeight(containerHeight: 40, topInset: 80) == 0)
        #expect(WorkspacePanelLayout.fittedTerminalHeight(configuredHeight: 220, availableHeight: 180) == 180)
        #expect(WorkspacePanelLayout.fittedTerminalHeight(configuredHeight: 220, availableHeight: -1) == 0)
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
