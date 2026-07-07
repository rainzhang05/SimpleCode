import Foundation

enum WorkspaceTrustState: String, Codable, Equatable, Sendable {
    case trusted
    case untrusted

    var isTrusted: Bool { self == .trusted }
}
