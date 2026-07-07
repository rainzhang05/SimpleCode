import Foundation

/// Tracks filesystem facts needed to prove a partial clone destination is safe to delete.
struct CloneDestinationOwnership: Sendable, Equatable {
    let destinationURL: URL
    let parentURL: URL
    let existedBeforeClone: Bool
    let identityAtStart: FileIdentity?
    var identityAfterGitCreate: FileIdentity?
    var inodeAfterGitCreate: UInt64?

    init(destinationURL: URL, existedBeforeClone: Bool) {
        self.destinationURL = destinationURL.standardizedFileURL
        self.parentURL = destinationURL.deletingLastPathComponent().standardizedFileURL
        self.existedBeforeClone = existedBeforeClone
        if existedBeforeClone, FileManager.default.fileExists(atPath: destinationURL.path) {
            self.identityAtStart = FileIdentity(url: destinationURL)
        } else {
            self.identityAtStart = nil
        }
    }

    mutating func captureIdentityIfDestinationAppeared() {
        guard !existedBeforeClone else { return }
        guard identityAfterGitCreate == nil else { return }
        guard FileManager.default.fileExists(atPath: destinationURL.path) else { return }
        identityAfterGitCreate = FileIdentity(url: destinationURL)
        inodeAfterGitCreate = Self.inode(for: destinationURL)
    }

    /// Returns whether the service may remove the partial destination after git has exited.
    func canRemovePartialDestination(processHasExited: Bool) -> Bool {
        guard processHasExited else { return false }
        guard !existedBeforeClone else { return false }
        guard FileManager.default.fileExists(atPath: destinationURL.path) else { return false }
        guard isDestinationInsideParent() else { return false }

        guard let ownedIdentity = identityAfterGitCreate,
              let ownedInode = inodeAfterGitCreate else {
            return false
        }

        let currentIdentity = FileIdentity(url: destinationURL)
        guard currentIdentity.isSameFile(as: ownedIdentity) else { return false }
        guard let currentInode = Self.inode(for: destinationURL), currentInode == ownedInode else {
            return false
        }
        return true
    }

    private func isDestinationInsideParent() -> Bool {
        let destPath = destinationURL.standardizedFileURL.path
        let parentPath = parentURL.standardizedFileURL.path
        guard destPath != parentPath else { return false }
        let prefix = parentPath.hasSuffix("/") ? parentPath : parentPath + "/"
        return destPath.hasPrefix(prefix)
    }

    private static func inode(for url: URL) -> UInt64? {
        var statInfo = stat()
        guard lstat(url.path, &statInfo) == 0 else { return nil }
        return UInt64(statInfo.st_ino)
    }
}
