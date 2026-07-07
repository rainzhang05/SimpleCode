import Foundation

enum TextEncodingMode: String, Equatable, Sendable, Codable {
    case utf8
    case utf8WithBOM
    case utf16LittleEndian
    case utf16BigEndian
    case isoLatin1

    var displayName: String {
        switch self {
        case .utf8: return "UTF-8"
        case .utf8WithBOM: return "UTF-8 BOM"
        case .utf16LittleEndian: return "UTF-16 LE"
        case .utf16BigEndian: return "UTF-16 BE"
        case .isoLatin1: return "ISO-8859-1"
        }
    }

    var stringEncoding: String.Encoding {
        switch self {
        case .utf8, .utf8WithBOM: return .utf8
        case .utf16LittleEndian: return .utf16LittleEndian
        case .utf16BigEndian: return .utf16BigEndian
        case .isoLatin1: return .isoLatin1
        }
    }

    var includesBOM: Bool {
        switch self {
        case .utf8WithBOM, .utf16LittleEndian, .utf16BigEndian: return true
        case .utf8, .isoLatin1: return false
        }
    }
}
