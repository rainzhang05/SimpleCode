import Foundation
import UniformTypeIdentifiers

struct RecentlyClosedDocument: Equatable, Sendable {
    let fileURL: URL
    let displayName: String
}

@MainActor
@Observable
final class OpenDocumentsStore {
    private(set) var sessions: [EditorDocumentSession] = []
    private(set) var activeSessionID: UUID?
    private(set) var recentlyClosed: [RecentlyClosedDocument] = []
    private let maxRecentlyClosed = 10

    private let loader: any FileContentLoading
    private let fileOperations = FileOperationService()
    private let watcherRegistry = DocumentWatcherRegistry()
    private var latestOpenRequest = 0
    var saveAsCoordinator: SavePanelCoordinating = SaveAsCoordinator()
    var appSettings: AppSettingsStore?

    var pendingLargeFileOpen: PendingLargeFileOpen?

    init(loader: any FileContentLoading = FileContentLoader()) {
        self.loader = loader
    }

    var activeSession: EditorDocumentSession? {
        guard let activeSessionID else { return nil }
        return sessions.first { $0.id == activeSessionID }
    }

    func session(for identity: FileIdentity) -> EditorDocumentSession? {
        sessions.first { $0.fileIdentity?.isSameFile(as: identity) == true }
    }

    func session(for url: URL) -> EditorDocumentSession? {
        session(for: FileIdentity(url: url))
    }

    func activate(_ session: EditorDocumentSession) {
        activeSessionID = session.id
    }

    func activate(id: UUID) {
        activeSessionID = id
    }

    func open(url: URL) async {
        let request = beginOpenRequest()
        do {
            let metadata = try await loader.metadata(for: url)
            guard isLatestOpenRequest(request) else { return }
            if metadata.openPolicy != .normal {
                pendingLargeFileOpen = PendingLargeFileOpen(url: url, byteCount: metadata.byteCount, policy: metadata.openPolicy)
                return
            }
            await open(url: url, choice: nil, request: request)
        } catch {
            guard isLatestOpenRequest(request) else { return }
            await open(url: url, choice: nil, request: request)
        }
    }

    func completeLargeFileOpen(choice: LargeFileOpenChoice) async {
        guard let pending = pendingLargeFileOpen else { return }
        pendingLargeFileOpen = nil
        guard choice != .cancel else { return }
        let request = beginOpenRequest()
        await open(url: pending.url, choice: choice, request: request)
    }

    func open(url: URL, choice: LargeFileOpenChoice?) async {
        let request = beginOpenRequest()
        await open(url: url, choice: choice, request: request)
    }

    private func open(url: URL, choice: LargeFileOpenChoice?, request: Int) async {
        guard isLatestOpenRequest(request) else { return }
        let identity = FileIdentity(url: url)
        if let existing = session(for: identity), existing.loadState != .loading {
            activate(existing)
            return
        }

        let session = EditorDocumentSession(displayName: url.lastPathComponent, fileURL: url)
        session.setLoading()
        sessions.append(session)
        activate(session)

        do {
            let content = try await loader.load(url: url, choice: choice)
            guard isCurrentOpenRequest(request, session: session) else {
                discardLoadingSession(session)
                return
            }
            session.prepareLoadedContent(content, url: url, choice: choice)
            await prepareInitialSyntax(for: session, text: content.text)
            guard isCurrentOpenRequest(request, session: session) else {
                discardLoadingSession(session)
                return
            }
            session.publishLoadedContent()
            startWatching(session: session)
        } catch FileLoadError.binary {
            guard isCurrentOpenRequest(request, session: session) else {
                discardLoadingSession(session)
                return
            }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            session.setBinaryPlaceholder(url: url, byteCount: Int64(values?.fileSize ?? 0))
            startWatching(session: session)
        } catch FileLoadError.permissionDenied {
            guard isCurrentOpenRequest(request, session: session) else {
                discardLoadingSession(session)
                return
            }
            session.setLoadError("Permission denied.", url: url)
        } catch FileLoadError.unsupportedEncoding {
            guard isCurrentOpenRequest(request, session: session) else {
                discardLoadingSession(session)
                return
            }
            session.setLoadError("Unsupported text encoding.", url: url)
        } catch {
            guard isCurrentOpenRequest(request, session: session) else {
                discardLoadingSession(session)
                return
            }
            session.setLoadError("Could not open file.", url: url)
        }
    }

    func openSample(text: String, displayName: String = "Sample.swift") {
        let session = EditorDocumentSession(displayName: displayName)
        session.configureSampleContent(text: text)
        sessions.append(session)
        activate(session)
    }

    @discardableResult
    func close(sessionID: UUID, force: Bool = false) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return true }
        let session = sessions[index]
        if session.isDirty && !force { return false }

        watcherRegistry.stopWatching(sessionID: sessionID)
        let recentlyClosedDocument = session.fileURL.map {
            RecentlyClosedDocument(fileURL: $0, displayName: session.displayName)
        }
        sessions.remove(at: index)
        session.releaseSyntaxResources()
        if let recentlyClosedDocument {
            recentlyClosed.insert(recentlyClosedDocument, at: 0)
            if recentlyClosed.count > maxRecentlyClosed {
                recentlyClosed.removeLast()
            }
        }

        if activeSessionID == sessionID {
            activeSessionID = sessions.last?.id
        }
        return true
    }

    func reopenLastClosed() async {
        guard let record = recentlyClosed.first else { return }
        recentlyClosed.removeFirst()
        await open(url: record.fileURL)
    }

    func closeOthers(than sessionID: UUID, force: Bool = false) -> [EditorDocumentSession] {
        let dirty = sessions.filter { $0.id != sessionID && $0.isDirty }
        if !force && !dirty.isEmpty { return dirty }
        for session in sessions where session.id != sessionID {
            watcherRegistry.stopWatching(sessionID: session.id)
            session.releaseSyntaxResources()
        }
        sessions.removeAll { $0.id != sessionID }
        if !sessions.contains(where: { $0.id == activeSessionID }) {
            activeSessionID = sessions.last?.id
        }
        return []
    }

    func closeToRight(of sessionID: UUID, force: Bool = false) -> [EditorDocumentSession] {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return [] }
        let dirty = Array(sessions[(index + 1)...]).filter(\.isDirty)
        if !force && !dirty.isEmpty { return dirty }
        for session in sessions[(index + 1)...] {
            watcherRegistry.stopWatching(sessionID: session.id)
            session.releaseSyntaxResources()
        }
        sessions = Array(sessions.prefix(index + 1))
        if !sessions.contains(where: { $0.id == activeSessionID }) {
            activeSessionID = sessions.last?.id
        }
        return []
    }

    func dirtySessions() -> [EditorDocumentSession] {
        sessions.filter(\.isDirty)
    }

    func updatePaths(from oldURL: URL, to newURL: URL) {
        let oldPath = oldURL.standardizedFileURL.path
        for session in sessions {
            guard let fileURL = session.fileURL else { continue }
            if fileURL.standardizedFileURL.path == oldPath {
                session.updateFileURL(newURL)
                watcherRegistry.retarget(session: session)
            }
        }
    }

    func updatePathsForMove(from oldURL: URL, to newURL: URL) {
        let oldPrefix = oldURL.standardizedFileURL.path + "/"
        for session in sessions {
            guard let fileURL = session.fileURL else { continue }
            let path = fileURL.standardizedFileURL.path
            if path == oldURL.standardizedFileURL.path {
                session.updateFileURL(newURL)
                watcherRegistry.retarget(session: session)
            } else if path.hasPrefix(oldPrefix) {
                let suffix = String(path.dropFirst(oldPrefix.count))
                session.updateFileURL(newURL.appendingPathComponent(suffix))
                watcherRegistry.retarget(session: session)
            }
        }
    }

    func saveActive() async throws {
        guard let session = activeSession, let url = session.fileURL else { return }
        try await save(session: session, to: url)
    }

    func save(session: EditorDocumentSession, to url: URL) async throws {
        let snapshot = await fileOperations.fileSnapshot(at: url)
        if let lastDate = session.lastKnownModificationDate,
           let currentDate = snapshot.modificationDate,
           currentDate > lastDate,
           session.lastKnownByteCount != snapshot.byteCount,
           session.externalChangeState == .none {
            session.setExternalChangeState(session.isDirty ? .dirtyConflict : .cleanReloadAvailable)
            throw FileOperationError.externalModificationConflict
        }

        let serialized = serializedText(for: session)
        let request = FileContentWriter.WriteRequest(
            url: url,
            text: serialized,
            encoding: session.encoding,
            includeBOM: session.hadBOM || session.encoding.includesBOM,
            lineEnding: session.lineEnding
        )
        _ = try await fileOperations.save(request: request)
        if serialized != session.textStorage.string {
            session.applySavedText(serialized)
        }
        let newSnapshot = await fileOperations.fileSnapshot(at: url)
        session.markClean(snapshot: newSnapshot)
        watcherRegistry.updateSnapshot(for: session)
    }

    func saveAll() async throws {
        for session in sessions where session.isDirty {
            guard let url = session.fileURL else { continue }
            try await save(session: session, to: url)
        }
    }

    func saveAs(session: EditorDocumentSession) async throws {
        guard let sourceURL = session.fileURL else { return }
        let directory = sourceURL.deletingLastPathComponent()
        let ext = sourceURL.pathExtension
        let types: [UTType] = ext.isEmpty ? [.plainText] : (UTType(filenameExtension: ext).map { [$0] } ?? [.plainText])
        guard let destination = await saveAsCoordinator.presentSavePanel(
            suggestedDirectory: directory,
            suggestedName: sourceURL.lastPathComponent,
            allowedContentTypes: types
        ) else {
            throw FileOperationError.cancelled
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            let confirmed = await saveAsCoordinator.confirmOverwrite(for: destination)
            guard confirmed else { throw FileOperationError.cancelled }
        }
        try await saveAs(session: session, to: destination)
    }

    func saveAs(session: EditorDocumentSession, to destination: URL) async throws {
        let destinationIdentity = FileIdentity(url: destination)
        if let existing = self.session(for: destinationIdentity), existing.id != session.id {
            activate(existing)
            throw FileOperationError.nameCollision
        }

        let previousURL = session.fileURL
        let wasDirty = session.isDirty
        do {
            try await save(session: session, to: destination)
            session.updateFileURL(destination)
            watcherRegistry.retarget(session: session)
        } catch {
            if let previousURL {
                session.updateFileURL(previousURL)
            }
            if wasDirty { session.markDirty() }
            throw error
        }
    }

    func reloadFromDisk(session: EditorDocumentSession) async {
        guard let url = session.fileURL else { return }
        do {
            let content = try await loader.load(url: url, choice: nil)
            let selection = session.selectionRange
            let scroll = session.scrollOffset
            session.prepareLoadedContent(content, url: url)
            await prepareInitialSyntax(for: session, text: content.text)
            session.publishLoadedContent()
            session.selectionRange = selection
            session.scrollOffset = scroll
            session.pendingSelectionRange = selection
            if session.enablesSyntaxHighlighting && session.highlighter == nil {
                session.highlighter = HighlightProviderFactory.makeHighlighter(for: session.language)
            }
            watcherRegistry.updateSnapshot(for: session)
        } catch {
            session.setLoadError("Could not reload file.", url: url)
        }
    }

    func tearDown() {
        _ = beginOpenRequest()
        watcherRegistry.stopAll()
        for session in sessions {
            session.textStorage.delegate = nil
            session.releaseSyntaxResources()
        }
        sessions.removeAll()
        activeSessionID = nil
        recentlyClosed.removeAll()
        pendingLargeFileOpen = nil
    }

    private func serializedText(for session: EditorDocumentSession) -> String {
        let raw = session.textStorage.string
        guard let settings = appSettings else { return raw }
        return SaveTransformService.transform(
            text: raw,
            language: session.language,
            lineEnding: session.lineEnding,
            trimTrailingWhitespace: settings.editor.trimTrailingWhitespaceOnSave,
            ensureFinalNewline: settings.editor.ensureFinalNewlineOnSave
        )
    }

    private func startWatching(session: EditorDocumentSession) {
        watcherRegistry.startWatching(session: session) { [weak self] session, event in
            self?.handleWatchEvent(session: session, event: event)
        }
    }

    private func prepareInitialSyntax(for session: EditorDocumentSession, text: String) async {
        guard session.enablesSyntaxHighlighting,
              let highlighter = HighlightProviderFactory.makeHighlighter(for: session.language) else {
            session.highlighter = nil
            return
        }
        session.highlighter = highlighter
        let batch = await highlighter.load(text: text, revision: session.revision)
        guard !Task.isCancelled, session.revision == batch.revision else { return }
        session.applyInitialHighlighting(batch)
    }

    private func beginOpenRequest() -> Int {
        latestOpenRequest &+= 1
        return latestOpenRequest
    }

    private func isLatestOpenRequest(_ request: Int) -> Bool {
        request == latestOpenRequest
    }

    private func isCurrentOpenRequest(_ request: Int, session: EditorDocumentSession) -> Bool {
        isLatestOpenRequest(request) && sessions.contains { $0.id == session.id }
    }

    private func discardLoadingSession(_ session: EditorDocumentSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        watcherRegistry.stopWatching(sessionID: session.id)
        sessions.remove(at: index)
        session.releaseSyntaxResources()
        if activeSessionID == session.id {
            activeSessionID = sessions.last?.id
        }
    }

    private func handleWatchEvent(session: EditorDocumentSession, event: FileWatchEvent) {
        switch event {
        case .deleted:
            session.setExternalChangeState(.deleted)
        case .modified, .replaced:
            if session.isDirty {
                session.setExternalChangeState(.dirtyConflict)
            } else {
                session.setExternalChangeState(.cleanReloadAvailable)
            }
        }
    }
}
