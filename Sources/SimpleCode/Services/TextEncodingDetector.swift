import Foundation

enum TextEncodingDetector {
    struct Result: Equatable, Sendable {
        let encoding: TextEncodingMode
        let hadBOM: Bool
    }

    static func detect(in data: Data) -> Result? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return Result(encoding: .utf8WithBOM, hadBOM: true)
        }
        if data.starts(with: [0xFF, 0xFE]) {
            return Result(encoding: .utf16LittleEndian, hadBOM: true)
        }
        if data.starts(with: [0xFE, 0xFF]) {
            return Result(encoding: .utf16BigEndian, hadBOM: true)
        }

        if let _ = String(data: data, encoding: .utf8) {
            return Result(encoding: .utf8, hadBOM: false)
        }

        if let _ = String(data: data, encoding: .utf16LittleEndian) {
            return Result(encoding: .utf16LittleEndian, hadBOM: false)
        }
        if let _ = String(data: data, encoding: .utf16BigEndian) {
            return Result(encoding: .utf16BigEndian, hadBOM: false)
        }
        if let _ = String(data: data, encoding: .isoLatin1) {
            return Result(encoding: .isoLatin1, hadBOM: false)
        }
        return nil
    }

    static func decode(_ data: Data, encoding: TextEncodingMode, hadBOM: Bool) -> String? {
        var payload = data
        if hadBOM {
            switch encoding {
            case .utf8WithBOM where payload.starts(with: [0xEF, 0xBB, 0xBF]):
                payload = payload.dropFirst(3)
            case .utf16LittleEndian where payload.starts(with: [0xFF, 0xFE]):
                payload = payload.dropFirst(2)
            case .utf16BigEndian where payload.starts(with: [0xFE, 0xFF]):
                payload = payload.dropFirst(2)
            default:
                break
            }
        }
        return String(data: payload, encoding: encoding.stringEncoding)
    }
}
