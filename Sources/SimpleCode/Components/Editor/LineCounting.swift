import Foundation

/// Pure, UI-independent line counting, kept separate from `LineNumberGutterView` so
/// it can be unit tested without a live `NSTextView`/`NSTextLayoutManager`.
enum LineCounting {
    /// The 1-based line number of the line containing UTF-16 offset `utf16Offset`
    /// within `text`. Counts newline (`\n`) code units strictly before the offset.
    static func lineNumber(atUTF16Offset utf16Offset: Int, in text: String) -> Int {
        guard utf16Offset > 0 else { return 1 }

        let utf16View = text.utf16
        let clampedOffset = min(utf16Offset, utf16View.count)
        guard let endIndex = utf16View.index(utf16View.startIndex, offsetBy: clampedOffset, limitedBy: utf16View.endIndex) else {
            return 1
        }

        var line = 1
        var index = utf16View.startIndex
        while index < endIndex {
            if utf16View[index] == 10 { // "\n"
                line += 1
            }
            index = utf16View.index(after: index)
        }
        return line
    }

    /// The UTF-16 offset of the first code unit on 1-based `line` within `text`.
    static func lineStartUTF16Offset(forLine line: Int, in text: String) -> Int {
        guard line > 1 else { return 0 }

        let utf16View = text.utf16
        var currentLine = 1
        var index = utf16View.startIndex
        while index < utf16View.endIndex {
            if currentLine == line {
                return utf16View.distance(from: utf16View.startIndex, to: index)
            }
            if utf16View[index] == 10 {
                currentLine += 1
            }
            index = utf16View.index(after: index)
        }
        return utf16View.count
    }
}
