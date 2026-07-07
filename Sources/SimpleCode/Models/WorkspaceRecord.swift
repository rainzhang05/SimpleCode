import Foundation

/// A single entry in the recent-workspaces list.
///
/// `id` is generated once, at creation time, and is retained for the lifetime of the
/// record. It is **not** derived from bookmark data or a path hash — bookmark bytes
/// are an opaque, potentially-changing resolution mechanism, not a stable identity.
struct WorkspaceRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var displayName: String
    /// Best-effort resolved filesystem path, as of the last successful resolution.
    /// Used for display and as a lookup key when re-opening the same folder; it is
    /// not treated as a permanent identifier.
    var path: String
    /// Bookmark data for the folder, when it could be created. May be `nil` if
    /// bookmark creation failed; the record remains usable via `path` in that case.
    var bookmarkData: Data?
    var lastOpenedDate: Date
    /// Set when the record could not be resolved to an existing folder on disk.
    /// Unavailable records are kept (not silently deleted) so the user can decide
    /// whether to remove them.
    var isUnavailable: Bool

    init(
        id: UUID = UUID(),
        displayName: String,
        path: String,
        bookmarkData: Data?,
        lastOpenedDate: Date = Date(),
        isUnavailable: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.path = path
        self.bookmarkData = bookmarkData
        self.lastOpenedDate = lastOpenedDate
        self.isUnavailable = isUnavailable
    }
}
