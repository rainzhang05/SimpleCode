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
}
