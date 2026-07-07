import Foundation

/// Stable identity for an open document tab. Prefers filesystem resource identifier
/// when available; otherwise uses a normalized absolute URL path.
struct FileIdentity: Hashable, Sendable, Equatable {
    let key: String
    let url: URL

    init(url: URL) {
        self.url = url
        if let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]),
           let identifier = values.fileResourceIdentifier {
            self.key = "fid:\(identifier)"
        } else {
            self.key = "path:\(url.standardizedFileURL.path)"
        }
    }

    func isSameFile(as other: FileIdentity) -> Bool {
        key == other.key
    }
}
