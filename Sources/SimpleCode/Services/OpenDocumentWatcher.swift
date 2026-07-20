import Darwin
import Foundation

struct FileWatchSnapshot: Equatable, Sendable {
    let modificationDate: Date?
    let byteCount: Int64
    let resourceID: Data?
}

enum FileWatchEvent: Sendable {
    case modified(FileWatchSnapshot)
    case deleted
    case replaced(FileWatchSnapshot)
}

/// Watches a single file using DispatchSource and optional parent-directory watch for atomic replacement.
@MainActor
final class OpenDocumentWatcher {
    private var fileSource: DispatchSourceFileSystemObject?
    private var parentSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var parentDescriptor: Int32 = -1
    private var watchedURL: URL?
    private var lastSnapshot: FileWatchSnapshot?
    private var onEvent: ((FileWatchEvent) -> Void)?

    func startWatching(url: URL, snapshot: FileWatchSnapshot, onEvent: @escaping (FileWatchEvent) -> Void) {
        stopWatching()
        watchedURL = url
        lastSnapshot = snapshot
        self.onEvent = onEvent
        openDescriptors(for: url)
    }

    func updateSnapshot(_ snapshot: FileWatchSnapshot) {
        lastSnapshot = snapshot
    }

    func retarget(to url: URL, snapshot: FileWatchSnapshot) {
        startWatching(url: url, snapshot: snapshot, onEvent: onEvent ?? { _ in })
    }

    func stopWatching() {
        fileSource?.cancel()
        parentSource?.cancel()
        fileSource = nil
        parentSource = nil
        fileDescriptor = -1
        parentDescriptor = -1
        watchedURL = nil
        lastSnapshot = nil
        onEvent = nil
    }

    private func openDescriptors(for url: URL) {
        let path = url.path
        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let fileSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: .main
        )
        fileSource.setEventHandler { [weak self] in
            self?.handleFileEvent()
        }
        let openedFileDescriptor = fileDescriptor
        fileSource.setCancelHandler {
            close(openedFileDescriptor)
        }
        self.fileSource = fileSource
        fileSource.resume()

        let parentPath = url.deletingLastPathComponent().path
        parentDescriptor = open(parentPath, O_EVTONLY)
        guard parentDescriptor >= 0 else { return }

        let parentSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: parentDescriptor,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: .main
        )
        parentSource.setEventHandler { [weak self] in
            self?.recheckFile()
        }
        let openedParentDescriptor = parentDescriptor
        parentSource.setCancelHandler {
            close(openedParentDescriptor)
        }
        self.parentSource = parentSource
        parentSource.resume()
    }

    private func handleFileEvent() {
        guard let url = watchedURL else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            onEvent?(.deleted)
            return
        }
        emitIfChanged(at: url)
    }

    private func recheckFile() {
        guard let url = watchedURL else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            onEvent?(.deleted)
            return
        }
        emitIfChanged(at: url)
    }

    private func emitIfChanged(at url: URL) {
        let current = Self.snapshot(for: url)
        guard let last = lastSnapshot else {
            lastSnapshot = current
            return
        }
        let changed = current.modificationDate != last.modificationDate
            || current.byteCount != last.byteCount
            || current.resourceID != last.resourceID
        guard changed else { return }
        let event: FileWatchEvent = current.resourceID != last.resourceID ? .replaced(current) : .modified(current)
        lastSnapshot = current
        onEvent?(event)
    }

    static func snapshot(for url: URL) -> FileWatchSnapshot {
        let values = try? url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey,
            .fileResourceIdentifierKey
        ])
        return FileWatchSnapshot(
            modificationDate: values?.contentModificationDate,
            byteCount: Int64(values?.fileSize ?? 0),
            resourceID: values?.fileResourceIdentifier as? Data
        )
    }
}
