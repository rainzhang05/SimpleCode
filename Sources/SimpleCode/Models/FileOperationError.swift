import Foundation

enum FileOperationError: Error, Equatable, Sendable, LocalizedError {
    case fileNotFound
    case permissionDenied
    case nameCollision
    case invalidFilename(String)
    case unsupportedEncoding
    case binaryFile
    case fileTooLarge(Int64)
    case readFailed(String)
    case saveFailed(String)
    case externalModificationConflict
    case moveIntoDescendant
    case trashFailed(String)
    case duplicateFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .fileNotFound: return "The file could not be found."
        case .permissionDenied: return "You don't have permission to access this file."
        case .nameCollision: return "An item with that name already exists."
        case .invalidFilename(let reason): return reason
        case .unsupportedEncoding: return "The file uses an unsupported text encoding."
        case .binaryFile: return "Binary files cannot be edited as text."
        case .fileTooLarge(let bytes):
            return "The file is too large to open (\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))."
        case .readFailed(let detail): return "Could not read file: \(detail)"
        case .saveFailed(let detail): return "Could not save file: \(detail)"
        case .externalModificationConflict: return "The file changed on disk since it was opened."
        case .moveIntoDescendant: return "Cannot move a folder into itself or a subfolder."
        case .trashFailed(let detail): return "Could not move to Trash: \(detail)"
        case .duplicateFailed(let detail): return "Could not duplicate: \(detail)"
        case .cancelled: return "The operation was cancelled."
        }
    }
}

struct FileOperationResult: Sendable {
    let url: URL
}
