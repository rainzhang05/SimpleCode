import Foundation

enum TextEncodingDetector {
    struct Result: Equatable, Sendable {
        let encoding: TextEncodingMode
        let hadBOM: Bool
        let text: String
    }

    static func detect(in data: Data) -> Result? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            if let text = String(data: data.dropFirst(3), encoding: .utf8) {
                return Result(encoding: .utf8WithBOM, hadBOM: true, text: text)
            }
            return nil
        }
        if data.starts(with: [0xFF, 0xFE]) {
            if let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) {
                return Result(encoding: .utf16LittleEndian, hadBOM: true, text: text)
            }
            return nil
        }
        if data.starts(with: [0xFE, 0xFF]) {
            if let text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) {
                return Result(encoding: .utf16BigEndian, hadBOM: true, text: text)
            }
            return nil
        }

        if let text = String(data: data, encoding: .utf8) {
            return Result(encoding: .utf8, hadBOM: false, text: text)
        }

        if let text = String(data: data, encoding: .utf16LittleEndian) {
            return Result(encoding: .utf16LittleEndian, hadBOM: false, text: text)
        }
        if let text = String(data: data, encoding: .utf16BigEndian) {
            return Result(encoding: .utf16BigEndian, hadBOM: false, text: text)
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return Result(encoding: .isoLatin1, hadBOM: false, text: text)
        }
        return nil
    }
}
