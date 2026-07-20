import Foundation

@MainActor
@Observable
final class AppModel {
    enum Route {
        case welcome
        case workspace(WorkspaceModel)
    }

    private(set) var route: Route = .welcome
    let recentWorkspaces: RecentWorkspaceStore
    let appSettings: AppSettingsStore
    let workspaceStateStore: WorkspaceStateStore
    let gitClone: GitCloneController
    let launchConfiguration: LaunchConfiguration
    var pendingWorkspaceURL: URL?
    var showCloneSheet = false

    init(
        recentWorkspaces: RecentWorkspaceStore? = nil,
        editorSettings: AppSettingsStore? = nil,
        workspaceStateStore: WorkspaceStateStore? = nil,
        launchConfiguration: LaunchConfiguration = .parse()
    ) {
        self.launchConfiguration = launchConfiguration
        let defaults = AppTestingSupport.makeUserDefaults(launchConfiguration: launchConfiguration)
        self.recentWorkspaces = recentWorkspaces ?? RecentWorkspaceStore(defaults: defaults)
        self.appSettings = editorSettings ?? AppSettingsStore(defaults: defaults)
        self.workspaceStateStore = workspaceStateStore ?? WorkspaceStateStore(defaults: defaults)
        self.gitClone = GitCloneController(
            recentWorkspaces: self.recentWorkspaces,
            workspaceStateStore: self.workspaceStateStore,
            clonePreferencesDefaults: defaults
        )
        self.gitClone.onCloneSuccess = { [weak self] destination in
            self?.handleCloneSuccess(destination: destination)
        }

        if AppTestingSupport.isUITesting(launchConfiguration: launchConfiguration),
           !launchConfiguration.uiTestSeedRecentWorkspacePaths.isEmpty {
            let urls = launchConfiguration.uiTestSeedRecentWorkspacePaths.map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
            self.recentWorkspaces.replaceForUITesting(urls: urls)
        }

        if let folderPath = launchConfiguration.openFolderPath {
            let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                let record = self.recentWorkspaces.recordOpened(url: folderURL)
                self.route = .workspace(WorkspaceModel(
                    id: record.id,
                    rootURL: folderURL,
                    appSettings: self.appSettings,
                    workspaceStateStore: self.workspaceStateStore,
                    useSyntaxStressSample: launchConfiguration.useSyntaxStressSample,
                    launchConfiguration: launchConfiguration
                ))
            }
        }
    }

    var workspace: WorkspaceModel? {
        if case .workspace(let model) = route { return model }
        return nil
    }

    var isWorkspaceOpen: Bool { workspace != nil }

    func openWorkspace(at url: URL) {
        if case .workspace(let existing) = route {
            if !existing.openDocuments.dirtySessions().isEmpty {
                pendingWorkspaceURL = url
                existing.unsavedSessionsForSheet = existing.openDocuments.dirtySessions()
                existing.pendingCloseAction = { [weak self] in
                    existing.tearDown()
                    self?.performOpenWorkspace(at: url)
                }
                return
            }
            existing.tearDown()
        }
        performOpenWorkspace(at: url)
    }

    private func performOpenWorkspace(at url: URL) {
        let record = recentWorkspaces.recordOpened(url: url)
        let workspace = WorkspaceModel(
            id: record.id,
            rootURL: url,
            appSettings: appSettings,
            workspaceStateStore: workspaceStateStore,
            launchConfiguration: launchConfiguration
        )
        route = .workspace(workspace)
        pendingWorkspaceURL = nil
        AppLog.app.info("Opened workspace")
        Task { await workspace.bootstrapAfterOpen() }
    }

    func closeWorkspace() {
        guard case .workspace(let workspace) = route else { return }
        workspace.requestCloseWorkspace { [weak self] in
            self?.route = .welcome
        }
    }

    func tearDownForTermination() {
        beginTerminationCleanup()
        if case .workspace(let workspace) = route {
            workspace.tearDown()
        }
    }

    /// Starts bounded cleanup without blocking AppKit's termination callback. The
    /// clone service owns signal escalation; waiting for it on the main actor can
    /// deadlock shutdown and was the source of the visible close-window stall.
    func beginTerminationCleanup() {
        gitClone.tearDownForTermination()
    }

    func handleCloneSuccess(destination: URL) {
        showCloneSheet = false
        openWorkspace(at: destination)
    }
}
