import Foundation

enum CommentToggleEngine {
    static func toggle(
        text: String,
        selection: NSRange,
        language: EditorCommandLanguage
    ) -> EditorCommandResult? {
        guard let prefix = language.lineCommentPrefix else { return nil }

        let lineRanges = EditorTextSupport.affectedLineRanges(for: selection, in: text)
        guard !lineRanges.isEmpty else { return nil }

        let nonBlankLines = lineRanges.filter { !EditorTextSupport.isBlankLine($0, in: text) }
        let targetLines = nonBlankLines.isEmpty ? lineRanges : nonBlankLines

        let allCommented = targetLines.allSatisfy { isLineCommented($0, prefix: prefix, in: text) }
        var edits: [TextEdit] = []

        for line in targetLines {
            if allCommented {
                if let edit = uncommentLine(line, prefix: prefix, in: text) {
                    edits.append(edit)
                }
            } else if let edit = commentLine(line, prefix: prefix, in: text) {
                edits.append(edit)
            }
        }

        guard !edits.isEmpty else { return nil }

        let newText = EditorTextSupport.applyEdits(edits, to: text)
        let newSelection = remapSelection(selection, edits: edits, newText: newText)
        return EditorCommandResult(edits: edits, resultingSelections: [newSelection])
    }

    private static func isLineCommented(_ lineRange: NSRange, prefix: String, in text: String) -> Bool {
        let content = EditorTextSupport.lineContentRange(at: lineRange.location, in: text)
        let ns = EditorTextSupport.nsString(text)
        let lineText = ns.substring(with: content)
        let trimmed = lineText.drop(while: { $0 == " " || $0 == "\t" })
        return trimmed.hasPrefix(prefix)
    }

    private static func commentLine(_ lineRange: NSRange, prefix: String, in text: String) -> TextEdit? {
        let insertAt = EditorTextSupport.firstNonWhitespaceOffset(on: lineRange, in: text)
        return TextEdit(range: NSRange(location: insertAt, length: 0), replacement: prefix + " ")
    }

    private static func uncommentLine(_ lineRange: NSRange, prefix: String, in text: String) -> TextEdit? {
        let content = EditorTextSupport.lineContentRange(at: lineRange.location, in: text)
        let ns = EditorTextSupport.nsString(text)
        let lineText = ns.substring(with: content)
        let leadingWS = lineText.prefix(while: { $0 == " " || $0 == "\t" })
        let afterWS = lineText.dropFirst(leadingWS.count)
        guard afterWS.hasPrefix(prefix) else { return nil }

        var removeLength = prefix.count
        if afterWS.dropFirst(prefix.count).first == " " {
            removeLength += 1
        }

        let rangeStart = content.location + leadingWS.count
        return TextEdit(range: NSRange(location: rangeStart, length: removeLength), replacement: "")
    }

    private static func remapSelection(_ selection: NSRange, edits: [TextEdit], newText: String) -> NSRange {
        var location = selection.location
        var length = selection.length
        let sorted = edits.sorted { $0.range.location < $1.range.location }
        for edit in sorted {
            if edit.range.location <= location {
                let delta = (edit.replacement as NSString).length - edit.range.length
                location += delta
            }
            if edit.range.location < selection.location + selection.length {
                let delta = (edit.replacement as NSString).length - edit.range.length
                if edit.range.location >= selection.location {
                    length += delta
                }
            }
        }
        return NSRange(location: location, length: max(0, length))
    }
}
