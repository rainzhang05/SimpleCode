import Foundation

enum WorkspaceOpenProvenance: Sendable, Equatable {
    case openedExisting
    case cloned
    case userCreated
}
