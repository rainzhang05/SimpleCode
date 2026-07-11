import Foundation

enum EditorTextSupport {
    static func nsString(_ text: String) -> NSString {
        text as NSString
    }

    static func lineRange(at location: Int, in text: String) -> NSRange {
        let ns = nsString(text)
        let clamped = max(0, min(location, ns.length))
        return ns.lineRange(for: NSRange(location: clamped, length: 0))
    }

    static func lineNumber(at location: Int, in text: String) -> Int {
        LineCounting.lineNumber(atUTF16Offset: location, in: text)
    }

    static func lineStart(at location: Int, in text: String) -> Int {
        lineRange(at: location, in: text).location
    }

    static func lineContentRange(at location: Int, in text: String) -> NSRange {
        let line = lineRange(at: location, in: text)
        let ns = nsString(text)
        var end = line.location + line.length
        while end > line.location {
            let terminator = ns.character(at: end - 1)
            guard terminator == 10 || terminator == 13 else { break }
            end -= 1
        }
        return NSRange(location: line.location, length: max(0, end - line.location))
    }

    static func leadingWhitespaceLength(on lineRange: NSRange, in text: String) -> Int {
        let ns = nsString(text)
        var count = 0
        let end = min(lineRange.location + lineRange.length, ns.length)
        var index = lineRange.location
        while index < end {
            let ch = ns.character(at: index)
            if ch == 32 || ch == 9 { // space or tab
                count += 1
                index += 1
            } else {
                break
            }
        }
        return count
    }

    static func leadingWhitespace(on lineRange: NSRange, in text: String) -> String {
        let ns = nsString(text)
        let length = leadingWhitespaceLength(on: lineRange, in: text)
        guard length > 0 else { return "" }
        return ns.substring(with: NSRange(location: lineRange.location, length: length))
    }

    static func visualColumn(of location: Int, in text: String, tabWidth: Int) -> Int {
        let lineStart = lineStart(at: location, in: text)
        let ns = nsString(text)
        var column = 0
        var index = lineStart
        while index < location && index < ns.length {
            let ch = ns.character(at: index)
            if ch == 9 {
                column += tabWidth - (column % tabWidth)
            } else {
                column += 1
            }
            index += 1
        }
        return column
    }

    static func locationForVisualColumn(
        _ targetColumn: Int,
        onLineStartingAt lineStart: Int,
        in text: String,
        tabWidth: Int
    ) -> Int {
        let ns = nsString(text)
        var column = 0
        var index = lineStart
        let line = lineRange(at: lineStart, in: text)
        let lineEnd = line.location + line.length
        while index < lineEnd && index < ns.length {
            if column >= targetColumn { return index }
            let ch = ns.character(at: index)
            if ch == 9 {
                let next = column + tabWidth - (column % tabWidth)
                if next > targetColumn { return index }
                column = next
            } else if ch == 10 || ch == 13 {
                break
            } else {
                column += 1
            }
            index += 1
        }
        return index
    }

    static func firstNonWhitespaceOffset(on lineRange: NSRange, in text: String) -> Int {
        let ns = nsString(text)
        let end = min(lineRange.location + lineRange.length, ns.length)
        var index = lineRange.location
        while index < end {
            let ch = ns.character(at: index)
            if ch != 32 && ch != 9 && ch != 10 && ch != 13 {
                return index
            }
            index += 1
        }
        return lineRange.location
    }

    static func isBlankLine(_ lineRange: NSRange, in text: String) -> Bool {
        let content = lineContentRange(at: lineRange.location, in: text)
        let ns = nsString(text)
        for index in content.location..<(content.location + content.length) {
            let ch = ns.character(at: index)
            if ch != 32 && ch != 9 { return false }
        }
        return true
    }

    static func lineEnding(in text: String) -> String {
        if text.contains("\r\n") { return "\r\n" }
        if text.contains("\r") { return "\r" }
        return "\n"
    }

    static func affectedLineRanges(for selection: NSRange, in text: String) -> [NSRange] {
        guard selection.length > 0 else {
            return [lineRange(at: selection.location, in: text)]
        }
        let startLine = lineRange(at: selection.location, in: text)
        let endLocation = selection.location + selection.length
        let endLine = lineRange(at: max(0, endLocation - 1), in: text)
        var ranges: [NSRange] = []
        var current = startLine.location
        let ns = nsString(text)
        while current <= endLine.location && current < ns.length {
            let range = ns.lineRange(for: NSRange(location: current, length: 0))
            ranges.append(range)
            current = range.location + range.length
            if current >= ns.length { break }
        }
        if ranges.isEmpty { ranges.append(startLine) }
        return ranges
    }

    static func applyEdits(_ edits: [TextEdit], to text: String) -> String {
        guard !edits.isEmpty else { return text }
        let sorted = edits.sorted { $0.range.location > $1.range.location }
        var result = text
        for edit in sorted {
            let ns = result as NSString
            result = ns.replacingCharacters(in: edit.range, with: edit.replacement)
        }
        return result
    }

    static func adjustSelections(
        _ selections: [NSRange],
        for edit: TextEdit,
        isBeforeEdit: Bool
    ) -> [NSRange] {
        let editStart = edit.range.location
        let editEnd = edit.range.location + edit.range.length
        let delta = (edit.replacement as NSString).length - edit.range.length
        return selections.map { selection in
            if selection.location + selection.length <= editStart {
                return selection
            }
            if selection.location >= editEnd {
                return NSRange(location: selection.location + delta, length: selection.length)
            }
            if isBeforeEdit {
                return NSRange(location: editStart, length: 0)
            }
            return NSRange(location: editStart + (edit.replacement as NSString).length, length: 0)
        }
    }

    /// Maps a selected range through a batch of non-overlapping edits expressed
    /// in the original document coordinate space. The leading boundary keeps an
    /// insertion at its edge selected; the trailing boundary includes it.
    static func adjustedSelection(_ selection: NSRange, for edits: [TextEdit]) -> NSRange {
        guard selection.length > 0 else { return selection }
        let sorted = edits.sorted { lhs, rhs in
            if lhs.range.location == rhs.range.location { return lhs.range.length < rhs.range.length }
            return lhs.range.location < rhs.range.location
        }
        let start = adjustedBoundary(selection.location, afterEdit: false, edits: sorted)
        let end = adjustedBoundary(NSMaxRange(selection), afterEdit: true, edits: sorted)
        return NSRange(location: start, length: max(0, end - start))
    }

    private static func adjustedBoundary(_ position: Int, afterEdit: Bool, edits: [TextEdit]) -> Int {
        var delta = 0
        for edit in edits {
            let start = edit.range.location
            let end = NSMaxRange(edit.range)
            let replacementLength = (edit.replacement as NSString).length

            if position < start || (position == start && !afterEdit) {
                break
            }
            if position > end || (position == end && afterEdit) {
                delta += replacementLength - edit.range.length
                continue
            }
            return start + delta + (afterEdit ? replacementLength : 0)
        }
        return position + delta
    }

    static func indentLevel(of whitespace: String, usesTabs: Bool, tabWidth: Int) -> Int {
        if usesTabs {
            return whitespace.filter { $0 == "\t" }.count
                + whitespace.filter { $0 == " " }.count / tabWidth
        }
        return whitespace.count / tabWidth
    }

    static func indentString(level: Int, options: IndentationOptions) -> String {
        guard level > 0 else { return "" }
        return String(repeating: options.indentUnit, count: level)
    }

    static func trimTrailingWhitespace(from line: String) -> String {
        var result = line
        while let last = result.unicodeScalars.last, CharacterSet.whitespaces.contains(last) {
            result.removeLast()
        }
        return result
    }

    static func character(at location: Int, in text: String) -> UInt16? {
        let ns = nsString(text)
        guard location >= 0, location < ns.length else { return nil }
        return ns.character(at: location)
    }

    static func substring(_ range: NSRange, in text: String) -> String {
        guard range.length > 0 else { return "" }
        return nsString(text).substring(with: range)
    }

    static func rangesOverlap(_ a: NSRange, _ b: NSRange) -> Bool {
        NSIntersectionRange(a, b).length > 0
    }
}
