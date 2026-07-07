import Foundation

enum LineEndingMode: String, Equatable, Sendable, Codable {
    case lf
    case crlf
    case cr
    case mixed

    var displayName: String {
        switch self {
        case .lf: return "LF"
        case .crlf: return "CRLF"
        case .cr: return "CR"
        case .mixed: return "Mixed"
        }
    }

    var newlineString: String {
        switch self {
        case .lf, .mixed: return "\n"
        case .crlf: return "\r\n"
        case .cr: return "\r"
        }
    }
}
