import Foundation

/// Bookmark helpers for workspace folders.
///
/// The app is not sandboxed (see architecture report §H), so *security-scoped*
/// bookmarks are unnecessary — plain bookmarks are still valuable because they let a
/// recent workspace be re-resolved correctly even if the folder is renamed or moved
/// within the same volume, which a stored path string alone cannot do.
enum WorkspaceFolderAccess {
    /// Creates plain (non security-scoped) bookmark data for `url`. Returns `nil` on
    /// failure rather than throwing, because bookmark creation is a best-effort
    /// enhancement — callers still have the resolved path to fall back on.
    static func makeBookmark(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            AppLog.filesystem.error("Failed to create bookmark for workspace folder: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    enum ResolutionResult {
        case resolved(URL)
        case failed
    }

    /// Resolves previously stored bookmark data back to a URL. Never throws or
    /// crashes on stale/invalid data — callers treat `.failed` as "mark unavailable".
    static func resolve(bookmark: Data) -> ResolutionResult {
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale {
                AppLog.filesystem.notice("Resolved a stale bookmark; caller should refresh it.")
            }
            return .resolved(url)
        } catch {
            AppLog.filesystem.error("Failed to resolve workspace bookmark: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }
}
