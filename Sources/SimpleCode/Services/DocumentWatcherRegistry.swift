import Foundation

@MainActor
final class DocumentWatcherRegistry {
    private var watchers: [UUID: OpenDocumentWatcher] = [:]

    func startWatching(session: EditorDocumentSession, handler: @escaping (EditorDocumentSession, FileWatchEvent) -> Void) {
        stopWatching(sessionID: session.id)
        guard let url = session.fileURL else { return }

        let snapshot = FileWatchSnapshot(
            modificationDate: session.lastKnownModificationDate,
            byteCount: session.lastKnownByteCount,
            resourceID: session.lastKnownResourceID
        )

        let watcher = OpenDocumentWatcher()
        watcher.startWatching(url: url, snapshot: snapshot) { [weak session] event in
            guard let session else { return }
            handler(session, event)
        }
        watchers[session.id] = watcher
    }

    func retarget(session: EditorDocumentSession) {
        guard let watcher = watchers[session.id], let url = session.fileURL else { return }
        let snapshot = FileWatchSnapshot(
            modificationDate: session.lastKnownModificationDate,
            byteCount: session.lastKnownByteCount,
            resourceID: session.lastKnownResourceID
        )
        watcher.retarget(to: url, snapshot: snapshot)
    }

    func updateSnapshot(for session: EditorDocumentSession) {
        guard let watcher = watchers[session.id] else { return }
        watcher.updateSnapshot(FileWatchSnapshot(
            modificationDate: session.lastKnownModificationDate,
            byteCount: session.lastKnownByteCount,
            resourceID: session.lastKnownResourceID
        ))
    }

    func stopWatching(sessionID: UUID) {
        watchers[sessionID]?.stopWatching()
        watchers.removeValue(forKey: sessionID)
    }

    func stopAll() {
        for (_, watcher) in watchers { watcher.stopWatching() }
        watchers.removeAll()
    }
}
