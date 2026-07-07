import Foundation

/// Pure validation for drag-and-drop and file move preflight.
enum MoveValidator {
    enum ValidationError: Equatable, Sendable, Error {
        case sourceNotInWorkspace
        case destinationNotInWorkspace
        case moveIntoDescendant
        case nameCollision
        case noOp
        case invalidDestination
    }

    static func validate(source: URL, destinationDirectory: URL, workspaceRoot: URL) -> Result<URL, ValidationError> {
        let source = source.standardizedFileURL
        let destinationDirectory = destinationDirectory.standardizedFileURL
        let workspaceRoot = workspaceRoot.standardizedFileURL

        let workspacePrefix = workspaceRoot.path + "/"
        guard source.path == workspaceRoot.path || source.path.hasPrefix(workspacePrefix) else {
            return .failure(.sourceNotInWorkspace)
        }
        guard destinationDirectory.path == workspaceRoot.path || destinationDirectory.path.hasPrefix(workspacePrefix) else {
            return .failure(.destinationNotInWorkspace)
        }
        guard destinationDirectory.hasDirectoryPath else {
            return .failure(.invalidDestination)
        }

        let destPath = destinationDirectory.path
        let sourcePath = source.path
        if destPath == sourcePath || destPath.hasPrefix(sourcePath + "/") {
            return .failure(.moveIntoDescendant)
        }

        let parent = source.deletingLastPathComponent().standardizedFileURL
        if parent == destinationDirectory {
            return .failure(.noOp)
        }

        let target = destinationDirectory.appendingPathComponent(source.lastPathComponent)
        if FileManager.default.fileExists(atPath: target.path) {
            return .failure(.nameCollision)
        }

        return .success(target)
    }
}
