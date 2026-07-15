import Foundation

/// Pure, UI-independent line counting, kept separate from `LineNumberGutterView` so
/// it can be unit tested without a live `NSTextView`/`NSTextLayoutManager`.
enum LineCounting {
    /// The 1-based line number of the line containing UTF-16 offset `utf16Offset`
    /// within `text`. Counts newline (`\n`) code units strictly before the offset.
    static func lineNumber(atUTF16Offset utf16Offset: Int, in text: String) -> Int {
        guard utf16Offset > 0 else { return 1 }
        var line = 1
        for codeUnit in text.utf16.prefix(utf16Offset) {
            if codeUnit == 10 { // "\n"
                line += 1
            }
        }
        return line
    }

    /// The UTF-16 offset of the first code unit on 1-based `line` within `text`.
    static func lineStartUTF16Offset(forLine line: Int, in text: String) -> Int {
        guard line > 1 else { return 0 }
        
        var currentLine = 1
        var offset = 0
        for codeUnit in text.utf16 {
            if currentLine == line {
                break
            }
            if codeUnit == 10 {
                currentLine += 1
            }
            offset += 1
        }
        return offset
    }
}
