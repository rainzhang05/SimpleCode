import Foundation
import UniformTypeIdentifiers

@MainActor
@Observable
final class OpenDocumentsStore {
    private(set) var sessions: [EditorDocumentSession] = []
    private(set) var activeSessionID: UUID?
    private(set) var recentlyClosed: [EditorDocumentSession] = []
    private let maxRecentlyClosed = 10

    private let loader = FileContentLoader()
    private let fileOperations = FileOperationService()
    private let watcherRegistry = DocumentWatcherRegistry()
    var saveAsCoordinator: SavePanelCoordinating = SaveAsCoordinator()
    var appSettings: AppSettingsStore?

    var pendingLargeFileOpen: PendingLargeFileOpen?

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
        do {
            let metadata = try await loader.metadata(for: url)
            if metadata.openPolicy != .normal {
                pendingLargeFileOpen = PendingLargeFileOpen(url: url, byteCount: metadata.byteCount, policy: metadata.openPolicy)
                return
            }
            await open(url: url, choice: nil)
        } catch {
            await open(url: url, choice: nil)
        }
    }

    func completeLargeFileOpen(choice: LargeFileOpenChoice) async {
        guard let pending = pendingLargeFileOpen else { return }
        pendingLargeFileOpen = nil
        guard choice != .cancel else { return }
        await open(url: pending.url, choice: choice)
    }

    func open(url: URL, choice: LargeFileOpenChoice?) async {
        let identity = FileIdentity(url: url)
        if let existing = session(for: identity) {
            activate(existing)
            return
        }

        let session = EditorDocumentSession(displayName: url.lastPathComponent, fileURL: url)
        session.setLoading()
        sessions.append(session)
        activate(session)

        do {
            let content = try await loader.load(url: url, choice: choice)
            session.applyLoadedContent(content, url: url, choice: choice)
            if session.enablesSyntaxHighlighting {
                session.highlighter = HighlightProviderFactory.makeHighlighter(for: session.language)
            }
            startWatching(session: session)
        } catch FileLoadError.binary {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            session.setBinaryPlaceholder(url: url, byteCount: Int64(values?.fileSize ?? 0))
            startWatching(session: session)
        } catch FileLoadError.permissionDenied {
            session.setLoadError("Permission denied.", url: url)
        } catch FileLoadError.unsupportedEncoding {
            session.setLoadError("Unsupported text encoding.", url: url)
        } catch {
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
        sessions.remove(at: index)
        session.releaseSyntaxResources()
        recentlyClosed.insert(session, at: 0)
        if recentlyClosed.count > maxRecentlyClosed {
            recentlyClosed.removeLast()
        }

        if activeSessionID == sessionID {
            activeSessionID = sessions.last?.id
        }
        return true
    }

    func reopenLastClosed() {
        guard let session = recentlyClosed.first else { return }
        recentlyClosed.removeFirst()
        if session.enablesSyntaxHighlighting && session.highlighter == nil {
            session.highlighter = HighlightProviderFactory.makeHighlighter(for: session.language)
        }
        sessions.append(session)
        activate(session)
        startWatching(session: session)
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
