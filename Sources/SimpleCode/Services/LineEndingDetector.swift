import Foundation

enum LineEndingDetector {
    static func detect(in text: String) -> LineEndingMode {
        var lf = 0
        var crlf = 0
        var cr = 0

        var previousWasCR = false
        for codeUnit in text.utf8 {
            if codeUnit == 10 { // LF
                if previousWasCR {
                    crlf += 1
                    cr -= 1
                } else {
                    lf += 1
                }
                previousWasCR = false
            } else if codeUnit == 13 { // CR
                cr += 1
                previousWasCR = true
            } else {
                previousWasCR = false
            }
        }

        let kinds = (lf > 0 ? 1 : 0) + (crlf > 0 ? 1 : 0) + (cr > 0 ? 1 : 0)
        if kinds > 1 { return .mixed }
        if crlf > 0 { return .crlf }
        if cr > 0 { return .cr }
        return .lf
    }
}
