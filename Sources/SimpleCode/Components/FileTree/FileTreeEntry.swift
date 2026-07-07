import Foundation

/// One row in the shallow (non-recursive) workspace file listing used by this phase.
/// Full recursive, lazily-loaded tree construction is explicitly deferred.
struct FileTreeEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let url: URL
    let isDirectory: Bool

    init(url: URL, isDirectory: Bool) {
        self.id = url.path
        self.name = url.lastPathComponent
        self.url = url
        self.isDirectory = isDirectory
    }
}
