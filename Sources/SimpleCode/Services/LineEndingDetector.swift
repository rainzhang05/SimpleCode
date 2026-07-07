import Foundation

enum LineEndingDetector {
    static func detect(in text: String) -> LineEndingMode {
        var lf = 0
        var crlf = 0
        var cr = 0

        let utf16 = Array(text.utf16)
        var index = 0
        while index < utf16.count {
            if utf16[index] == 13 {
                if index + 1 < utf16.count, utf16[index + 1] == 10 {
                    crlf += 1
                    index += 2
                    continue
                }
                cr += 1
            } else if utf16[index] == 10 {
                lf += 1
            }
            index += 1
        }

        let kinds = [lf > 0, crlf > 0, cr > 0].filter { $0 }.count
        if kinds > 1 { return .mixed }
        if crlf > 0 { return .crlf }
        if cr > 0 { return .cr }
        return .lf
    }
}
