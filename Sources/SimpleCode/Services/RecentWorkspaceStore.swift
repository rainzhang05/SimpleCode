import Foundation

/// Persists the recent-workspaces list to `UserDefaults` as JSON.
///
/// Identity rule (see architecture correction): a record's `id` is generated once and
/// retained; it is never derived from a hash of bookmark bytes. `path` is used only
/// as a lookup key to decide whether "open this folder" should update an existing
/// record or create a new one.
@MainActor
@Observable
final class RecentWorkspaceStore {
    private(set) var records: [WorkspaceRecord] = []

    private let defaults: UserDefaults
    private let storageKey: String
    private let maximumRecords = 20

    init(defaults: UserDefaults = .standard, storageKey: String = "recentWorkspaces.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        self.records = Self.decode(from: defaults, key: storageKey)
    }

    /// Records that a workspace at `url` was just opened: updates the existing entry
    /// (same UUID, refreshed date) if this path was already known, otherwise creates
    /// a new entry with a freshly generated UUID.
    @discardableResult
    func recordOpened(url: URL) -> WorkspaceRecord {
        let resolvedPath = url.standardizedFileURL.path
        let bookmark = WorkspaceFolderAccess.makeBookmark(for: url)

        if let index = records.firstIndex(where: { $0.path == resolvedPath }) {
            records[index].lastOpenedDate = Date()
            records[index].isUnavailable = false
            if let bookmark {
                records[index].bookmarkData = bookmark
            }
            let updated = records[index]
            moveToFront(id: updated.id)
            persist()
            return updated
        }

        let record = WorkspaceRecord(
            displayName: url.lastPathComponent,
            path: resolvedPath,
            bookmarkData: bookmark
        )
        records.insert(record, at: 0)
        trimIfNeeded()
        persist()
        return record
    }

    func remove(id: UUID) {
        records.removeAll { $0.id == id }
        persist()
    }

    func clearAll() {
        guard !records.isEmpty else { return }
        records.removeAll()
        persist()
    }

    /// Resolves a record back to an openable URL, preferring its bookmark (survives
    /// renames/moves on the same volume) and falling back to the stored path string.
    /// Marks the record `isUnavailable` (without deleting it) if neither works —
    /// the application must stay stable and let the user remove it explicitly.
    func resolvedURL(for id: UUID) -> URL? {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return nil }
        let record = records[index]

        if let bookmark = record.bookmarkData,
           case .resolved(let url) = WorkspaceFolderAccess.resolve(bookmark: bookmark),
           FileManager.default.fileExists(atPath: url.path) {
            records[index].isUnavailable = false
            persist()
            return url
        }

        let fallbackURL = URL(fileURLWithPath: record.path)
        if FileManager.default.fileExists(atPath: fallbackURL.path) {
            records[index].isUnavailable = false
            persist()
            return fallbackURL
        }

        records[index].isUnavailable = true
        persist()
        return nil
    }

    private func moveToFront(id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let record = records.remove(at: index)
        records.insert(record, at: 0)
    }

    private func trimIfNeeded() {
        if records.count > maximumRecords {
            records.removeLast(records.count - maximumRecords)
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(records)
            defaults.set(data, forKey: storageKey)
        } catch {
            AppLog.filesystem.error("Failed to persist recent workspaces: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func decode(from defaults: UserDefaults, key: String) -> [WorkspaceRecord] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([WorkspaceRecord].self, from: data)
        } catch {
            // Corrupted persisted state must never crash launch.
            AppLog.filesystem.error("Recent workspace data was corrupted; resetting. \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
