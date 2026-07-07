import Foundation

enum ExternalChangeState: Equatable, Sendable {
    case none
    case cleanReloadAvailable
    case dirtyConflict
    case deleted
}

enum LargeFileOpenChoice: Equatable, Sendable {
    case openNormally
    case openWithoutSyntax
    case openReadOnlyWithoutSyntax
    case openAnyway
    case cancel
}

struct PendingLargeFileOpen: Equatable, Sendable, Identifiable {
    var id: URL { url }
    let url: URL
    let byteCount: Int64
    let policy: FileSizeThresholds.OpenPolicy
}
