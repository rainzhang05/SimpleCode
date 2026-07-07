import Foundation

enum GitClonePhase: String, Sendable, Equatable {
    case counting
    case compressing
    case receiving
    case resolving
    case checkingOut
    case unknown

    var displayName: String {
        switch self {
        case .counting: "Counting objects"
        case .compressing: "Compressing objects"
        case .receiving: "Receiving objects"
        case .resolving: "Resolving deltas"
        case .checkingOut: "Checking out files"
        case .unknown: "Cloning"
        }
    }
}

struct GitCloneProgress: Sendable, Equatable {
    var phase: GitClonePhase
    var percentage: Double?
    var receivedObjects: Int?
    var totalObjects: Int?
    var statusMessage: String

    static let initial = GitCloneProgress(
        phase: .unknown,
        percentage: nil,
        receivedObjects: nil,
        totalObjects: nil,
        statusMessage: "Starting clone…"
    )
}

enum GitCloneError: LocalizedError, Equatable {
    case invalidRepositoryURL(String)
    case invalidDestinationName(String)
    case destinationExists
    case destinationNotWritable
    case gitUnavailable
    case authenticationFailure(String)
    case httpsCredentialUnavailable(String)
    case sshPermissionDenied(String)
    case networkFailure(String)
    case dnsFailure(String)
    case unknownSSHHost(String)
    case cancelled
    case processLaunchFailure(String)
    case nonzeroExit(Int32, String)
    case partialCleanupFailure(String)
    case workspaceOpenFailure(String)
    case cloneInProgress
    case emptyRepositoryURL

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryURL(let msg): return msg
        case .invalidDestinationName(let msg): return msg
        case .destinationExists: return "A folder already exists at the destination."
        case .destinationNotWritable: return "The destination folder is not writable."
        case .gitUnavailable: return "Git is not available. Install Xcode Command Line Tools to enable cloning."
        case .authenticationFailure(let msg): return msg
        case .httpsCredentialUnavailable(let msg): return msg
        case .sshPermissionDenied(let msg): return msg
        case .networkFailure(let msg): return msg
        case .dnsFailure(let msg): return msg
        case .unknownSSHHost(let msg): return msg
        case .cancelled: return "Clone was cancelled."
        case .processLaunchFailure(let msg): return msg
        case .nonzeroExit(let code, let msg): return "Git exited with status \(code). \(msg)"
        case .partialCleanupFailure(let msg): return msg
        case .workspaceOpenFailure(let msg): return msg
        case .cloneInProgress: return "A clone is already in progress."
        case .emptyRepositoryURL: return "Enter a repository URL."
        }
    }
}

struct GitParsedURL: Equatable, Sendable {
    let originalInput: String
    let normalizedURL: String
    let derivedFolderName: String
    let hadEmbeddedCredentials: Bool
}
