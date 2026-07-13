import CoreGraphics
import Foundation

enum WorkspacePanelLayout {
    static let defaultSidebarWidth: CGFloat = 280
    static let minimumSidebarWidth: CGFloat = 240
    static let maximumSidebarWidth: CGFloat = 360
    static let defaultTerminalHeight: CGFloat = 220
    static let minimumTerminalHeight: CGFloat = 120
    static let maximumTerminalHeight: CGFloat = 560

    static func clampedSidebarWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite else { return defaultSidebarWidth }
        return min(max(width, minimumSidebarWidth), maximumSidebarWidth)
    }

    static func clampedTerminalHeight(_ height: CGFloat) -> CGFloat {
        guard height.isFinite else { return defaultTerminalHeight }
        return min(max(height, minimumTerminalHeight), maximumTerminalHeight)
    }

    static func contentHeight(containerHeight: CGFloat, topInset: CGFloat) -> CGFloat {
        let height = max(0, containerHeight)
        let inset = min(max(0, topInset), height)
        return height - inset
    }

    static func fittedTerminalHeight(configuredHeight: CGFloat, availableHeight: CGFloat) -> CGFloat {
        min(clampedTerminalHeight(configuredHeight), max(0, availableHeight))
    }
}

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
    let runExecution: RunExecutionController
    let useSyntaxStressSample: Bool
    private let launchConfiguration: LaunchConfiguration
    private var bootstrapTask: Task<Void, Never>?
    private weak var editorMutationApplier: (any EditorTextMutationApplying)?
    private var editorMutationSessionID: UUID?
    private(set) var hasBootstrapped = false
    private(set) var isTornDown = false

    var findReplace = FindReplaceController()
    var goToLine = GoToLineController()
    var showLanguagePickerSheet = false
    var showRestartTerminalConfirmation = false

    private let fileOperations = FileOperationService()

    var isSidebarVisible: Bool = true
    var isTerminalVisible: Bool = false
    var sidebarWidth: CGFloat = WorkspacePanelLayout.defaultSidebarWidth {
        didSet {
            let clamped = WorkspacePanelLayout.clampedSidebarWidth(sidebarWidth)
            if clamped != sidebarWidth { sidebarWidth = clamped }
        }
    }
    var terminalHeight: CGFloat = WorkspacePanelLayout.defaultTerminalHeight {
        didSet {
            let clamped = WorkspacePanelLayout.clampedTerminalHeight(terminalHeight)
            if clamped != terminalHeight { terminalHeight = clamped }
        }
    }

    var unsavedSessionsForSheet: [EditorDocumentSession]?
    var pendingCloseAction: (() -> Void)?
    var errorAlertMessage: String?
    var pendingRename: PendingRename?
    var pendingCreation: PendingCreation?

    struct PendingRename: Identifiable {
        let id = UUID()
        let url: URL
        var name: String
    }

    enum CreationKind: String, Identifiable {
        case file
        case folder

        var id: String { rawValue }
        var title: String { self == .file ? "New File" : "New Folder" }
        var defaultName: String { self == .file ? "Untitled.swift" : "New Folder" }
    }

    struct PendingCreation: Identifiable {
        let id = UUID()
        let kind: CreationKind
        let directory: URL
        var name: String
    }

    static let minimumSidebarWidth = WorkspacePanelLayout.minimumSidebarWidth
    static let maximumSidebarWidth = WorkspacePanelLayout.maximumSidebarWidth
    static let minimumTerminalHeight = WorkspacePanelLayout.minimumTerminalHeight
    static let maximumTerminalHeight = WorkspacePanelLayout.maximumTerminalHeight

    init(
        id: UUID,
        rootURL: URL,
        appSettings: AppSettingsStore,
        workspaceStateStore: WorkspaceStateStore,
        useSyntaxStressSample: Bool = false,
        launchConfiguration: LaunchConfiguration = .parse()
    ) {
        self.id = id
        self.rootURL = rootURL
        self.appSettings = appSettings
        self.useSyntaxStressSample = useSyntaxStressSample
        self.fileTree = FileTreeModel(
            workspaceRoot: rootURL,
            userExclusions: appSettings.files.userExclusions
        )
        self.openDocuments = OpenDocumentsStore()
        self.terminal = TerminalSessionController(workingDirectory: rootURL)
        self.runCommands = RunCommandStore(
            workspaceID: id,
            rootURL: rootURL,
            stateStore: workspaceStateStore
        )
        self.launchConfiguration = launchConfiguration
        self.runExecution = RunExecutionController()
        self.runExecution.bind(workspace: self)
        self.terminal.onShellTerminated = { [weak self] in
            self?.runExecution.resetStateForNewRun()
        }
        self.openDocuments.appSettings = appSettings
    }

    func bootstrapAfterOpen() async {
        guard !isTornDown, !hasBootstrapped else { return }
        if let bootstrapTask {
            await bootstrapTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.syncFileTreeFromSettings()
            await self.fileTree.loadRoot()
            guard !Task.isCancelled, !self.isTornDown else { return }

            await self.runCommands.refreshSuggestion(rootURL: self.rootURL)
            guard !Task.isCancelled, !self.isTornDown else { return }

            if self.useSyntaxStressSample, self.openDocuments.sessions.isEmpty {
                self.openDocuments.openSample(text: SampleSwiftSource.generateLarge(), displayName: "StressSample.swift")
            }
            if let command = self.launchConfiguration.uiTestRunCommand {
                self.runCommands.setCommand(command, explicit: true)
            }
            self.hasBootstrapped = true
        }
        bootstrapTask = task
        await task.value
        bootstrapTask = nil
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

    func beginCreateNewFile(in directory: URL? = nil) {
        beginCreation(kind: .file, in: directory)
    }

    func beginCreateNewFolder(in directory: URL? = nil) {
        beginCreation(kind: .folder, in: directory)
    }

    private func beginCreation(kind: CreationKind, in directory: URL?) {
        let destination = directory ?? fileTree.destinationDirectoryForCreation()
        pendingCreation = PendingCreation(
            kind: kind,
            directory: destination,
            name: uniqueName(base: kind.defaultName, in: destination)
        )
    }

    func createNewFile(in directory: URL? = nil) async {
        let dir = directory ?? fileTree.destinationDirectoryForCreation()
        await createNewFile(named: uniqueName(base: CreationKind.file.defaultName, in: dir), in: dir)
    }

    func createNewFile(named name: String, in directory: URL) async {
        do {
            let result = try await fileOperations.createFile(at: directory, name: name)
            await fileTree.refresh()
            await openFile(url: result.url)
            pendingCreation = nil
        } catch {
            errorAlertMessage = error.localizedDescription
        }
    }

    func createNewFolder(in directory: URL? = nil) async {
        let dir = directory ?? fileTree.destinationDirectoryForCreation()
        await createNewFolder(named: uniqueName(base: CreationKind.folder.defaultName, in: dir), in: dir)
    }

    func createNewFolder(named name: String, in directory: URL) async {
        do {
            let result = try await fileOperations.createFolder(at: directory, name: name)
            await fileTree.refresh()
            fileTree.selectedNodeID = FileTreeNodeID(url: result.url)
            fileTree.expandedNodeIDs.insert(FileTreeNodeID(url: directory))
            pendingCreation = nil
        } catch {
            errorAlertMessage = error.localizedDescription
        }
    }

    func createPendingItem(named rawName: String) async {
        guard let pendingCreation else { return }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let validation = creationValidationError(for: name, in: pendingCreation.directory) {
            errorAlertMessage = validation
            return
        }
        switch pendingCreation.kind {
        case .file:
            await createNewFile(named: name, in: pendingCreation.directory)
        case .folder:
            await createNewFolder(named: name, in: pendingCreation.directory)
        }
    }

    func creationValidationError(for rawName: String, in directory: URL) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = FilenameValidator.validate(name) { return error }
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
            return "An item named \"\(name)\" already exists."
        }
        return nil
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
        syncFindBinding()
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

    func requestCloseWorkspace(onConfirmed: @escaping () -> Void) {
        if isTornDown {
            onConfirmed()
            return
        }
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
        guard !isTornDown else { return }
        isTornDown = true
        bootstrapTask?.cancel()
        bootstrapTask = nil
        pendingCloseAction = nil
        unsavedSessionsForSheet = nil
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
    }

    func showFind() {
        findReplace.showFind()
        syncFindBinding()
    }

    func showReplace() {
        findReplace.showReplace()
        syncFindBinding()
    }

    func findNext() {
        guard let range = findReplace.findNext() else { return }
        selectEditorRange(range)
    }

    func findPrevious() {
        guard let range = findReplace.findPrevious() else { return }
        selectEditorRange(range)
    }

    func replaceCurrent() {
        guard let session = openDocuments.activeSession else { return }
        let text = session.textStorage.string
        guard let result = findReplace.replaceCurrentEdit(in: text, selection: session.selectionRange) else { return }
        applyEditorCommand(
            EditorCommandResult(edits: [result.edit], resultingSelections: [result.selection]),
            session: session
        )
    }

    func replaceAll() {
        guard let session = openDocuments.activeSession else { return }
        guard let result = findReplace.replaceAllEdits(in: session.textStorage.string) else { return }
        applyEditorCommand(
            EditorCommandResult(edits: result.edits, resultingSelections: [result.selection]),
            session: session
        )
    }

    func showGoToLine() {
        guard let session = openDocuments.activeSession else { return }
        goToLine.show(currentLine: session.cursorLine)
    }

    func goToLineOffset(_ offset: Int) {
        guard openDocuments.activeSession != nil else { return }
        selectEditorRange(NSRange(location: offset, length: 0))
        goToLine.dismiss()
    }

    @discardableResult
    func syncFileTreeFromSettings() -> Bool {
        fileTree.applyUserExclusions(appSettings.files.userExclusions)
    }

    func refreshFileTreeIfSettingsChanged() async {
        guard syncFileTreeFromSettings() else { return }
        await fileTree.refresh()
    }

    func syncFindBinding() {
        guard findReplace.isVisible, let session = openDocuments.activeSession else { return }
        findReplace.bind(text: session.textStorage.string, selection: session.selectionRange)
    }

    private func selectEditorRange(_ range: NSRange) {
        guard let session = openDocuments.activeSession else { return }
        session.pendingSelectionRange = range
        session.selectionRange = range
        let line = session.lineStartIndex.lineNumber(atUTF16Offset: range.location)
        let lineStart = session.lineStartIndex.lineStartUTF16Offset(forLine: line)
        session.updateCursor(line: line, column: range.location - lineStart + 1)
    }

    func applyEditorCommand(_ result: EditorCommandResult, session: EditorDocumentSession) {
        if editorMutationSessionID == session.id,
           editorMutationApplier?.applyEditorMutation(result, to: session) == true {
            return
        }
        applyTextEdits(
            result.edits,
            selection: result.resultingSelections.first ?? session.selectionRange,
            session: session
        )
    }

    private func applyCommandResult(_ result: EditorCommandResult, session: EditorDocumentSession) {
        applyEditorCommand(result, session: session)
    }

    func registerEditorMutationApplier(_ applier: any EditorTextMutationApplying, for session: EditorDocumentSession) {
        editorMutationApplier = applier
        editorMutationSessionID = session.id
    }

    func unregisterEditorMutationApplier(_ applier: any EditorTextMutationApplying, for session: EditorDocumentSession) {
        guard editorMutationSessionID == session.id,
              let registeredApplier = editorMutationApplier,
              ObjectIdentifier(registeredApplier) == ObjectIdentifier(applier) else { return }
        editorMutationApplier = nil
        editorMutationSessionID = nil
    }

    private func applyTextEdits(_ edits: [TextEdit], selection: NSRange, session: EditorDocumentSession) {
        if !edits.isEmpty {
            let hadStorageDelegate = session.textStorage.delegate != nil
            let sortedEdits = edits.sorted { lhs, rhs in
                if lhs.range.location == rhs.range.location {
                    return lhs.range.length > rhs.range.length
                }
                return lhs.range.location > rhs.range.location
            }
            session.textStorage.beginEditing()
            for edit in sortedEdits where edit.range.location >= 0 && NSMaxRange(edit.range) <= session.textStorage.length {
                session.textStorage.replaceCharacters(in: edit.range, with: edit.replacement)
            }
            session.textStorage.endEditing()
            session.lineStartIndex.rebuild(from: session.textStorage.string)
            if !hadStorageDelegate {
                session.bumpRevision()
                session.markDirty()
            }
        }

        session.pendingSelectionRange = selection
        session.selectionRange = selection
        findReplace.bind(text: session.textStorage.string, selection: selection)
    }

    func activeEditorCommandController(for session: EditorDocumentSession) -> EditorCommandController {
        EditorCommandController(
            indentationOptions: IndentationOptions(
                language: commandLanguage(for: session),
                usesTabs: !effectiveInsertSpaces(for: session),
                tabWidth: appSettings.editor.tabWidth
            ),
            tabWidth: appSettings.editor.tabWidth,
            smartPairDeletionEnabled: appSettings.editor.smartPairDeletion
        )
    }

    func editorReturnResult(for session: EditorDocumentSession, selection: NSRange) -> EditorCommandResult? {
        guard selection.length == 0 else { return nil }
        return activeEditorCommandController(for: session).returnKey(
            text: session.textStorage.string,
            cursorLocation: selection.location
        )
    }

    func editorTabResult(for session: EditorDocumentSession, selection: NSRange, shift: Bool) -> EditorCommandResult? {
        let controller = activeEditorCommandController(for: session)
        if shift {
            return controller.outdent(text: session.textStorage.string, selection: selection)
        }
        return controller.indent(text: session.textStorage.string, selection: selection)
    }

    func editorBackspaceResult(for session: EditorDocumentSession, selection: NSRange) -> EditorCommandResult? {
        activeEditorCommandController(for: session).backspace(text: session.textStorage.string, selection: selection)
    }

    func editorHomeResult(
        for session: EditorDocumentSession,
        selection: NSRange,
        isSecondPress: Bool,
        extendSelection: Bool = false
    ) -> EditorCommandResult? {
        activeEditorCommandController(for: session).home(
            text: session.textStorage.string,
            selection: selection,
            isSecondPress: isSecondPress,
            extendSelection: extendSelection
        )
    }

    func editorPairInsertResult(
        for session: EditorDocumentSession,
        character: Character,
        selection: NSRange
    ) -> EditorCommandResult? {
        activeEditorCommandController(for: session).insertPair(
            character: character,
            text: session.textStorage.string,
            selection: selection,
            syntaxContext: session.syntaxContext
        )
    }

    private func activeCommandController() -> EditorCommandController {
        guard let session = openDocuments.activeSession else {
            return activeEditorCommandController(for: EditorDocumentSession())
        }
        return activeEditorCommandController(for: session)
    }

    private func effectiveInsertSpaces(for session: EditorDocumentSession) -> Bool {
        let definition = LanguageRegistry.definition(for: session.language)
        if let override = definition.insertSpacesOverride { return override }
        return appSettings.editor.insertSpaces
    }

    private func effectiveInsertSpaces() -> Bool {
        guard let session = openDocuments.activeSession else { return appSettings.editor.insertSpaces }
        return effectiveInsertSpaces(for: session)
    }

    private func commandLanguage(for session: EditorDocumentSession?) -> EditorCommandLanguage {
        guard let session else { return .plainText }
        switch session.language {
        case .swift: return .swift
        case .c, .cpp, .javascript, .typescript, .tsx, .json: return .cStyle
        case .python: return .python
        case .shell:
            let name = session.fileURL?.lastPathComponent.lowercased()
            return name == "makefile" || name == "gnumakefile" ? .makefile : .shell
        case .assembly: return .plainText
        case .markdown, .plainText: return .plainText
        }
    }

    func toggleLineComment() {
        guard let session = openDocuments.activeSession else { return }
        let controller = activeCommandController()
        guard let result = controller.toggleComment(text: session.textStorage.string, selection: session.selectionRange) else { return }
        applyCommandResult(result, session: session)
    }

    func duplicateLine() {
        guard let session = openDocuments.activeSession else { return }
        let result = activeCommandController().duplicateLine(text: session.textStorage.string, selection: session.selectionRange)
        applyCommandResult(result, session: session)
    }

    func moveLineUp() {
        guard let session = openDocuments.activeSession else { return }
        guard let result = activeCommandController().moveLineUp(text: session.textStorage.string, selection: session.selectionRange) else { return }
        applyCommandResult(result, session: session)
    }

    func moveLineDown() {
        guard let session = openDocuments.activeSession else { return }
        guard let result = activeCommandController().moveLineDown(text: session.textStorage.string, selection: session.selectionRange) else { return }
        applyCommandResult(result, session: session)
    }

    func deleteLine() {
        guard let session = openDocuments.activeSession else { return }
        let result = activeCommandController().deleteLine(text: session.textStorage.string, selection: session.selectionRange)
        applyCommandResult(result, session: session)
    }

    func indentSelection() {
        guard let session = openDocuments.activeSession else { return }
        let result = activeCommandController().indent(text: session.textStorage.string, selection: session.selectionRange)
        applyCommandResult(result, session: session)
    }

    func outdentSelection() {
        guard let session = openDocuments.activeSession else { return }
        let result = activeCommandController().outdent(text: session.textStorage.string, selection: session.selectionRange)
        applyCommandResult(result, session: session)
    }

    func convertIndentToSpaces() {
        guard let session = openDocuments.activeSession else { return }
        let result = activeCommandController().convertIndentToSpaces(text: session.textStorage.string, selection: session.selectionRange)
        applyCommandResult(result, session: session)
    }

    func convertIndentToTabs() {
        guard let session = openDocuments.activeSession else { return }
        let result = activeCommandController().convertIndentToTabs(text: session.textStorage.string, selection: session.selectionRange)
        applyCommandResult(result, session: session)
    }

    func trimTrailingWhitespace() {
        guard let session = openDocuments.activeSession else { return }
        let result = activeCommandController().trimTrailingWhitespace(text: session.textStorage.string, selection: session.selectionRange)
        applyCommandResult(result, session: session)
    }

    func toggleWordWrap() {
        appSettings.editor.wordWrap.toggle()
    }

    func toggleWhitespace() {
        appSettings.editor.showWhitespace.toggle()
        appSettings.editor.showTrailingWhitespace = appSettings.editor.showWhitespace
    }

    func toggleLineNumbers() {
        appSettings.editor.showLineNumbers.toggle()
    }

    func showLanguagePicker() {
        showLanguagePickerSheet = true
    }

    func setLanguage(_ language: LanguageID) {
        guard let session = openDocuments.activeSession else { return }
        session.setLanguageOverride(language)
        showLanguagePickerSheet = false
    }

    private func uniqueName(base: String, in directory: URL) -> String {
        var candidate = base
        var index = 1
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            let ext = (base as NSString).pathExtension
            let stem = (base as NSString).deletingPathExtension
            candidate = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            index += 1
        }
        return candidate
    }
}
