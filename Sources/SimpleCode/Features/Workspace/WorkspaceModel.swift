import CoreGraphics
import Foundation

@MainActor
@Observable
final class WorkspaceModel {
    let id: UUID
    let rootURL: URL
    var fileTree: FileTreeModel
    var openDocuments: OpenDocumentsStore
    let terminal: TerminalSessionController
    let appSettings: AppSettingsStore
    let runCommands: RunCommandStore
    let trust: WorkspaceTrustController
    let runExecution: RunExecutionController
    let useSyntaxStressSample: Bool
    private let launchConfiguration: LaunchConfiguration

    var findReplace = FindReplaceController()
    var goToLine = GoToLineController()
    var showLanguagePickerSheet = false
    var showRestartTerminalConfirmation = false

    private let fileOperations = FileOperationService()

    var isSidebarVisible: Bool = true
    var isTerminalVisible: Bool = false
    var terminalHeight: CGFloat = 220 {
        didSet {
            let clamped = min(max(terminalHeight, Self.minimumTerminalHeight), Self.maximumTerminalHeight)
            if clamped != terminalHeight { terminalHeight = clamped }
        }
    }

    var unsavedSessionsForSheet: [EditorDocumentSession]?
    var pendingCloseAction: (() -> Void)?
    var errorAlertMessage: String?
    var pendingRename: PendingRename?

    struct PendingRename: Identifiable {
        let id = UUID()
        let url: URL
        var name: String
    }

    static let minimumTerminalHeight: CGFloat = 120
    static let maximumTerminalHeight: CGFloat = 560

    init(
        id: UUID,
        rootURL: URL,
        appSettings: AppSettingsStore,
        workspaceStateStore: WorkspaceStateStore,
        provenance: WorkspaceOpenProvenance = .openedExisting,
        useSyntaxStressSample: Bool = false,
        launchConfiguration: LaunchConfiguration = .parse()
    ) {
        self.id = id
        self.rootURL = rootURL
        self.appSettings = appSettings
        self.useSyntaxStressSample = useSyntaxStressSample
        self.fileTree = FileTreeModel(workspaceRoot: rootURL)
        self.openDocuments = OpenDocumentsStore()
        self.terminal = TerminalSessionController(workingDirectory: rootURL)
        self.runCommands = RunCommandStore(
            workspaceID: id,
            rootURL: rootURL,
            stateStore: workspaceStateStore
        )
        self.trust = WorkspaceTrustController(
            workspaceID: id,
            stateStore: workspaceStateStore,
            provenance: provenance,
            rootURL: rootURL
        )
        self.launchConfiguration = launchConfiguration
        self.runExecution = RunExecutionController()
        self.runExecution.bind(workspace: self)
        self.terminal.onShellTerminated = { [weak self] in
            self?.runExecution.resetStateForNewRun()
        }
        self.openDocuments.appSettings = appSettings
        fileTree.showHiddenFiles = appSettings.files.showHiddenFiles
        fileTree.userExclusions = appSettings.files.userExclusions
    }

    func bootstrapAfterOpen() async {
        syncFileTreeFromSettings()
        await fileTree.loadRoot()
        await runCommands.refreshSuggestion(rootURL: rootURL)
        if let command = launchConfiguration.uiTestRunCommand {
            runCommands.setCommand(command, explicit: true)
        }
        if launchConfiguration.uiTestTrustDecision == "trusted" {
            trust.markTrusted()
        }
    }

    func bootstrapDocumentsIfNeeded() async {
        if useSyntaxStressSample {
            openDocuments.openSample(text: SampleSwiftSource.generateLarge(), displayName: "StressSample.swift")
            return
        }
        if openDocuments.sessions.isEmpty {
            // No sample in normal flow — workspace opens empty until user picks a file.
        }
    }

    func toggleSidebar() { isSidebarVisible.toggle() }

    func toggleTerminal() {
        isTerminalVisible.toggle()
        terminal.setPanelVisible(isTerminalVisible)
    }

    func openFile(url: URL) async {
        fileTree.activeFileURL = url
        fileTree.selectedNodeID = FileTreeNodeID(url: url)
        await openDocuments.open(url: url)
    }

    func createNewFile(in directory: URL? = nil) async {
        let dir = directory ?? fileTree.destinationDirectoryForCreation()
        let name = "Untitled.swift"
        do {
            let result = try await fileOperations.createFile(at: dir, name: uniqueName(base: name, in: dir))
            await fileTree.refresh()
            await openFile(url: result.url)
        } catch {
            errorAlertMessage = error.localizedDescription
        }
    }

    func createNewFolder(in directory: URL? = nil) async {
        let dir = directory ?? fileTree.destinationDirectoryForCreation()
        do {
            let result = try await fileOperations.createFolder(at: dir, name: uniqueName(base: "New Folder", in: dir))
            await fileTree.refresh()
            fileTree.selectedNodeID = FileTreeNodeID(url: result.url)
            fileTree.expandedNodeIDs.insert(FileTreeNodeID(url: dir))
        } catch {
            errorAlertMessage = error.localizedDescription
        }
    }

    func rename(item: URL, to newName: String) async {
        do {
            let result = try await fileOperations.rename(item: item, to: newName)
            openDocuments.updatePaths(from: item, to: result.url)
            await fileTree.refresh()
            fileTree.selectedNodeID = FileTreeNodeID(url: result.url)
            fileTree.activeFileURL = result.url
        } catch {
            errorAlertMessage = error.localizedDescription
        }
    }

    func renameSelectedItem(to newName: String) async {
        guard let nodeID = fileTree.selectedNodeID else { return }
        let url = nodeID.url
        await rename(item: url, to: newName)
    }

    func beginRenameSelectedItem() -> (URL, String)? {
        guard let nodeID = fileTree.selectedNodeID else { return nil }
        return (nodeID.url, nodeID.url.lastPathComponent)
    }

    func moveItem(from source: URL, to destinationDirectory: URL) async {
        switch MoveValidator.validate(source: source, destinationDirectory: destinationDirectory, workspaceRoot: rootURL) {
        case .failure(let error):
            switch error {
            case .noOp: return
            case .nameCollision: errorAlertMessage = FileOperationError.nameCollision.localizedDescription
            case .moveIntoDescendant: errorAlertMessage = FileOperationError.moveIntoDescendant.localizedDescription
            default: errorAlertMessage = "Cannot move item."
            }
            return
        case .success:
            do {
                let result = try await fileOperations.move(item: source, to: destinationDirectory)
                openDocuments.updatePathsForMove(from: source, to: result.url)
                await fileTree.refresh()
                fileTree.selectedNodeID = FileTreeNodeID(url: result.url)
            } catch {
                errorAlertMessage = error.localizedDescription
            }
        }
    }

    func saveAsActive() async {
        guard let session = openDocuments.activeSession else { return }
        do {
            try await openDocuments.saveAs(session: session)
            if let url = session.fileURL {
                fileTree.activeFileURL = url
                fileTree.selectedNodeID = FileTreeNodeID(url: url)
            }
            await fileTree.refresh()
        } catch FileOperationError.cancelled {
            // User cancelled panel.
        } catch FileOperationError.nameCollision {
            // Activated existing tab.
        } catch {
            errorAlertMessage = error.localizedDescription
        }
    }

    func reloadActiveFromDisk() async {
        guard let session = openDocuments.activeSession else { return }
        await openDocuments.reloadFromDisk(session: session)
    }

    func dismissExternalChange(for session: EditorDocumentSession) {
        session.dismissExternalChange()
    }

    func duplicate(item: URL) async {
        do {
            let result = try await fileOperations.duplicate(item: item)
            await fileTree.refresh()
            if !item.hasDirectoryPath {
                await openFile(url: result.url)
            }
        } catch {
            errorAlertMessage = error.localizedDescription
        }
    }

    func requestDelete(item: URL, isDirectory: Bool) {
        let message = isDirectory ? "Move folder to Trash?" : "Move file to Trash?"
        // Present via alert binding in view — store pending action
        pendingDeleteURL = item
        pendingDeleteIsDirectory = isDirectory
        errorAlertMessage = message
    }

    var pendingDeleteURL: URL?
    var pendingDeleteIsDirectory = false

    func confirmDelete() async {
        guard let url = pendingDeleteURL else { return }
        pendingDeleteURL = nil
        do {
            _ = try await fileOperations.trash(item: url)
            if let session = openDocuments.session(for: url) {
                if session.isDirty {
                    session.updateFileURL(url) // keep content as recovered untitled-like
                } else {
                    openDocuments.close(sessionID: session.id, force: true)
                }
            }
            await fileTree.refresh()
        } catch {
            errorAlertMessage = error.localizedDescription
        }
    }

    func save(session: EditorDocumentSession) async throws {
        try await openDocuments.save(session: session, to: session.fileURL!)
    }

    func saveActive() async throws { try await openDocuments.saveActive() }
    func saveAll() async throws { try await openDocuments.saveAll() }

    func requestCloseTab(sessionID: UUID) {
        guard let session = openDocuments.sessions.first(where: { $0.id == sessionID }) else { return }
        if session.isDirty {
            unsavedSessionsForSheet = [session]
            pendingCloseAction = { [weak self] in
                self?.openDocuments.close(sessionID: sessionID, force: true)
            }
            return
        }
        openDocuments.close(sessionID: sessionID)
    }

    func requestCloseOthers(than sessionID: UUID) {
        let dirty = openDocuments.closeOthers(than: sessionID, force: false)
        if dirty.isEmpty {
            _ = openDocuments.closeOthers(than: sessionID, force: true)
            return
        }
        unsavedSessionsForSheet = dirty
        pendingCloseAction = { [weak self] in
            _ = self?.openDocuments.closeOthers(than: sessionID, force: true)
        }
    }

    func requestCloseToRight(of sessionID: UUID) {
        let dirty = openDocuments.closeToRight(of: sessionID, force: false)
        if dirty.isEmpty {
            _ = openDocuments.closeToRight(of: sessionID, force: true)
            return
        }
        unsavedSessionsForSheet = dirty
        pendingCloseAction = { [weak self] in
            _ = self?.openDocuments.closeToRight(of: sessionID, force: true)
        }
    }

    func handleUnsavedSheet(_ action: UnsavedCloseAction) async {
        let sessions = unsavedSessionsForSheet ?? []
        unsavedSessionsForSheet = nil
        switch action {
        case .cancel:
            pendingCloseAction = nil
        case .dontSave:
            pendingCloseAction?()
            pendingCloseAction = nil
        case .save:
            do {
                for session in sessions {
                    if let url = session.fileURL { try await openDocuments.save(session: session, to: url) }
                }
                pendingCloseAction?()
                pendingCloseAction = nil
            } catch {
                errorAlertMessage = error.localizedDescription
            }
        }
    }

    func canCloseWorkspace() -> Bool {
        !openDocuments.dirtySessions().isEmpty
    }

    func requestCloseWorkspace(onConfirmed: @escaping () -> Void) {
        let dirty = openDocuments.dirtySessions()
        if dirty.isEmpty {
            tearDown()
            onConfirmed()
            return
        }
        unsavedSessionsForSheet = dirty
        pendingCloseAction = { [weak self] in
            self?.tearDown()
            onConfirmed()
        }
    }

    func tearDown() {
        runExecution.resetStateForNewRun()
        openDocuments.tearDown()
        terminal.terminate()
    }

    func activateNextTab() {
        guard let active = openDocuments.activeSessionID,
              let index = openDocuments.sessions.firstIndex(where: { $0.id == active }) else { return }
        let next = openDocuments.sessions[(index + 1) % openDocuments.sessions.count]
        openDocuments.activate(next)
    }

    func activatePreviousTab() {
        guard let active = openDocuments.activeSessionID,
              let index = openDocuments.sessions.firstIndex(where: { $0.id == active }) else { return }
        let count = openDocuments.sessions.count
        let previous = openDocuments.sessions[(index + count - 1) % count]
        openDocuments.activate(previous)
