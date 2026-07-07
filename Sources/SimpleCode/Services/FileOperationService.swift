import Foundation

actor FileOperationService {
    private let fileManager = FileManager.default

    func uniqueURL(for baseURL: URL, preferredName: String) -> URL {
        var candidate = baseURL.appendingPathComponent(preferredName)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let ext = candidate.pathExtension
        let stem = candidate.deletingPathExtension().lastPathComponent
        var index = 1
        while fileManager.fileExists(atPath: candidate.path) {
            let nextName = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            candidate = baseURL.appendingPathComponent(nextName)
            index += 1
        }
        return candidate
    }

    func createFile(at directory: URL, name: String) throws -> FileOperationResult {
        if let error = FilenameValidator.validate(name) {
            throw FileOperationError.invalidFilename(error)
        }
        let url = directory.appendingPathComponent(name)
        guard !fileManager.fileExists(atPath: url.path) else {
            throw FileOperationError.nameCollision
        }
        guard fileManager.createFile(atPath: url.path, contents: Data(), attributes: nil) else {
            throw FileOperationError.saveFailed("Could not create file.")
        }
        return FileOperationResult(url: url)
    }

    func createFolder(at directory: URL, name: String) throws -> FileOperationResult {
        if let error = FilenameValidator.validate(name) {
            throw FileOperationError.invalidFilename(error)
        }
        let url = directory.appendingPathComponent(name)
        guard !fileManager.fileExists(atPath: url.path) else {
            throw FileOperationError.nameCollision
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
        return FileOperationResult(url: url)
    }

    func rename(item: URL, to newName: String) throws -> FileOperationResult {
        if let error = FilenameValidator.validate(newName) {
            throw FileOperationError.invalidFilename(error)
        }
        let destination = item.deletingLastPathComponent().appendingPathComponent(newName)
        if FileManager.default.fileExists(atPath: destination.path) {
            // Case-only rename on case-insensitive volumes needs a temp hop.
            let samePathDifferentCase = destination.path.lowercased() == item.path.lowercased()
                && destination.lastPathComponent != item.lastPathComponent
            if samePathDifferentCase {
                return try caseOnlyRename(item: item, to: newName)
            }
            throw FileOperationError.nameCollision
        }
        try fileManager.moveItem(at: item, to: destination)
        return FileOperationResult(url: destination)
    }

    private func caseOnlyRename(item: URL, to newName: String) throws -> FileOperationResult {
        let parent = item.deletingLastPathComponent()
        let ext = (newName as NSString).pathExtension
        let tempName = ".simplecode-rename-\(UUID().uuidString)" + (ext.isEmpty ? "" : ".\(ext)")
        let tempURL = parent.appendingPathComponent(tempName)
        let finalURL = parent.appendingPathComponent(newName)
        try fileManager.moveItem(at: item, to: tempURL)
        do {
            try fileManager.moveItem(at: tempURL, to: finalURL)
        } catch {
            try? fileManager.moveItem(at: tempURL, to: item)
            throw error
        }
        return FileOperationResult(url: finalURL)
    }

    func move(item: URL, to directory: URL) throws -> FileOperationResult {
        let destination = directory.appendingPathComponent(item.lastPathComponent)
        let itemPath = item.standardizedFileURL.path
        let directoryPath = directory.standardizedFileURL.path
        if directoryPath.hasPrefix(itemPath + "/") {
            throw FileOperationError.moveIntoDescendant
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw FileOperationError.nameCollision
        }
        try fileManager.moveItem(at: item, to: destination)
        return FileOperationResult(url: destination)
    }

    func duplicate(item: URL) throws -> FileOperationResult {
        let parent = item.deletingLastPathComponent()
        let copyName = "copy of \(item.lastPathComponent)"
        let destination = uniqueURL(for: parent, preferredName: copyName)
        try fileManager.copyItem(at: item, to: destination)
        return FileOperationResult(url: destination)
    }

    func trash(item: URL) throws -> FileOperationResult {
        var resultingURL: NSURL?
        do {
            try fileManager.trashItem(at: item, resultingItemURL: &resultingURL)
            return FileOperationResult(url: item)
        } catch {
            throw FileOperationError.trashFailed(error.localizedDescription)
        }
    }

    func save(request: FileContentWriter.WriteRequest) throws -> FileOperationResult {
        do {
            return try FileContentWriter.writeAtomically(request)
        } catch let error as FileOperationError {
            throw error
        } catch {
            throw FileOperationError.saveFailed(error.localizedDescription)
        }
    }

    func fileSnapshot(at url: URL) -> (modificationDate: Date?, byteCount: Int64, resourceID: Data?) {
        let values = try? url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey,
            .fileResourceIdentifierKey
        ])
        let resourceID = values?.fileResourceIdentifier as? Data
        return (
            values?.contentModificationDate,
            Int64(values?.fileSize ?? 0),
            resourceID
        )
    }
}
