import Foundation

/// Centralized file-size policy for opening and editing documents.
enum FileSizeThresholds {
    /// Strong warning; syntax highlighting may be disabled.
    static let warningBytes: Int64 = 5 * 1_024 * 1_024

    /// Read-only or reduced-feature mode recommended.
    static let readOnlyRecommendedBytes: Int64 = 20 * 1_024 * 1_024

    enum OpenPolicy: Equatable, Sendable {
        case normal
        case warnLargeFile
        case readOnlyRecommended
    }

    static func openPolicy(forByteCount count: Int64) -> OpenPolicy {
        if count > readOnlyRecommendedBytes { return .readOnlyRecommended }
        if count > warningBytes { return .warnLargeFile }
        return .normal
    }
}
