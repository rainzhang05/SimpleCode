import Foundation

enum LineCommandEngine {
    static func duplicateLine(
        text: String,
        selection: NSRange
    ) -> EditorCommandResult {
        let lineRanges = EditorTextSupport.affectedLineRanges(for: selection, in: text)
        guard let lastLine = lineRanges.last else {
            return EditorCommandResult(edits: [], resultingSelections: [selection])
        }
        let ns = EditorTextSupport.nsString(text)
        let lineText = ns.substring(with: lastLine)
        let lineEndsWithTerminator: Bool
        if lastLine.length > 0 {
            let lastUnit = ns.character(at: lastLine.location + lastLine.length - 1)
            lineEndsWithTerminator = lastUnit == 10 || lastUnit == 13
        } else {
            lineEndsWithTerminator = true
        }
        let replacement = lineEndsWithTerminator
            ? lineText
            : EditorTextSupport.lineEnding(in: text) + lineText
        let edit = TextEdit(
            range: NSRange(location: lastLine.location + lastLine.length, length: 0),
            replacement: replacement
        )
        let newCursor = lastLine.location + lastLine.length + (replacement as NSString).length
        return EditorCommandResult(
            edits: [edit],
            resultingSelections: [NSRange(location: newCursor, length: 0)]
        )
    }

    static func moveLineUp(
        text: String,
        selection: NSRange
    ) -> EditorCommandResult? {
        let lines = EditorTextSupport.affectedLineRanges(for: selection, in: text)
        guard let first = lines.first, let last = lines.last else { return nil }
        guard first.location > 0 else { return nil }

        let ns = EditorTextSupport.nsString(text)
        let prevLine = ns.lineRange(for: NSRange(location: first.location - 1, length: 0))
        let block = ns.substring(with: NSRange(
            location: first.location,
            length: last.location + last.length - first.location
        ))
        let prevText = ns.substring(with: prevLine)

        let deleteRange = NSRange(location: prevLine.location, length: prevLine.length + (block as NSString).length)
        let replacement = block + prevText
        let edit = TextEdit(range: deleteRange, replacement: replacement)
        let newStart = prevLine.location + (selection.location - first.location)
        return EditorCommandResult(
            edits: [edit],
            resultingSelections: [NSRange(location: newStart, length: selection.length)]
        )
    }

    static func moveLineDown(
        text: String,
        selection: NSRange
    ) -> EditorCommandResult? {
        let lines = EditorTextSupport.affectedLineRanges(for: selection, in: text)
        guard let first = lines.first, let last = lines.last else { return nil }
        let ns = EditorTextSupport.nsString(text)
        let blockEnd = last.location + last.length
        guard blockEnd < ns.length else { return nil }

        let nextLine = ns.lineRange(for: NSRange(location: blockEnd, length: 0))
        let block = ns.substring(with: NSRange(
            location: first.location,
            length: blockEnd - first.location
        ))
        let nextText = ns.substring(with: nextLine)

        let deleteRange = NSRange(location: first.location, length: blockEnd + nextLine.length - first.location)
        let replacement = nextText + block
        let edit = TextEdit(range: deleteRange, replacement: replacement)
        let newStart = nextLine.location + (selection.location - first.location)
        return EditorCommandResult(
            edits: [edit],
            resultingSelections: [NSRange(location: newStart, length: selection.length)]
        )
    }

    static func deleteLine(
        text: String,
        selection: NSRange
    ) -> EditorCommandResult {
        let lines = EditorTextSupport.affectedLineRanges(for: selection, in: text)
        guard let first = lines.first, let last = lines.last else {
            return EditorCommandResult(edits: [], resultingSelections: [selection])
        }
        let range = NSRange(location: first.location, length: last.location + last.length - first.location)
        let edit = TextEdit(range: range, replacement: "")
        return EditorCommandResult(
            edits: [edit],
            resultingSelections: [NSRange(location: first.location, length: 0)]
        )
    }

    static func indent(
        text: String,
        selection: NSRange,
        options: IndentationOptions
    ) -> EditorCommandResult {
        if selection.length == 0 {
            let ns = EditorTextSupport.nsString(text)
            let location = max(0, min(selection.location, ns.length))
            let insertion: String
            if options.usesTabs {
                insertion = "\t"
            } else {
                let column = EditorTextSupport.visualColumn(of: location, in: text, tabWidth: options.tabWidth)
                let count = options.tabWidth - (column % options.tabWidth)
                insertion = String(repeating: " ", count: count)
            }
            let edit = TextEdit(range: NSRange(location: location, length: 0), replacement: insertion)
            return EditorCommandResult(
                edits: [edit],
                resultingSelections: [NSRange(location: location + (insertion as NSString).length, length: 0)]
            )
        }

        let lines = EditorTextSupport.affectedLineRanges(for: selection, in: text)
        let unit = options.indentUnit
        var edits: [TextEdit] = []
        for line in lines {
            edits.append(TextEdit(range: NSRange(location: line.location, length: 0), replacement: unit))
        }
        return EditorCommandResult(
            edits: edits,
            resultingSelections: [EditorTextSupport.adjustedSelection(selection, for: edits)]
        )
    }

    static func outdent(
        text: String,
        selection: NSRange,
        options: IndentationOptions
    ) -> EditorCommandResult {
        let lines = EditorTextSupport.affectedLineRanges(for: selection, in: text)
        var edits: [TextEdit] = []
        var totalRemovedBeforeSelection = 0

        for line in lines {
            let wsLength = EditorTextSupport.leadingWhitespaceLength(on: line, in: text)
            guard wsLength > 0 else { continue }
            let ws = EditorTextSupport.leadingWhitespace(on: line, in: text)
            let removeCount = outdentAmount(for: ws, options: options)
            guard removeCount > 0 else { continue }
            if line.location < selection.location {
                totalRemovedBeforeSelection += removeCount
            }
            edits.append(TextEdit(
                range: NSRange(location: line.location, length: removeCount),
                replacement: ""
            ))
        }

        let resultingSelection: NSRange
        if selection.length == 0 {
            resultingSelection = NSRange(location: max(0, selection.location - totalRemovedBeforeSelection), length: 0)
        } else {
            resultingSelection = EditorTextSupport.adjustedSelection(selection, for: edits)
        }
        return EditorCommandResult(
            edits: edits,
            resultingSelections: [resultingSelection]
        )
    }

    static func convertIndentToSpaces(
        text: String,
        selection: NSRange,
        tabWidth: Int
    ) -> EditorCommandResult {
        convertIndent(text: text, selection: selection, toTabs: false, tabWidth: tabWidth)
    }

    static func convertIndentToTabs(
        text: String,
        selection: NSRange,
        tabWidth: Int
    ) -> EditorCommandResult {
        convertIndent(text: text, selection: selection, toTabs: true, tabWidth: tabWidth)
    }

    static func trimTrailingWhitespace(
        text: String,
        selection: NSRange
    ) -> EditorCommandResult {
        let lines = EditorTextSupport.affectedLineRanges(for: selection, in: text)
        var edits: [TextEdit] = []
        for line in lines {
            let content = EditorTextSupport.lineContentRange(at: line.location, in: text)
            let ns = EditorTextSupport.nsString(text)
            let lineText = ns.substring(with: content)
            let trimmed = EditorTextSupport.trimTrailingWhitespace(from: lineText)
            guard trimmed.count != lineText.count else { continue }
            edits.append(TextEdit(
                range: NSRange(location: content.location, length: content.length),
                replacement: trimmed
            ))
        }
        return EditorCommandResult(edits: edits, resultingSelections: [selection])
    }

    static func insertFinalNewline(text: String) -> EditorCommandResult? {
        let ns = EditorTextSupport.nsString(text)
        guard ns.length > 0 else {
            return EditorCommandResult(
                edits: [TextEdit(range: NSRange(location: 0, length: 0), replacement: "\n")],
                resultingSelections: [NSRange(location: 1, length: 0)]
            )
        }
        let lastChar = ns.character(at: ns.length - 1)
        guard lastChar != 10 && lastChar != 13 else { return nil }
        let ending = EditorTextSupport.lineEnding(in: text)
        let edit = TextEdit(range: NSRange(location: ns.length, length: 0), replacement: ending)
        return EditorCommandResult(
            edits: [edit],
            resultingSelections: [NSRange(location: ns.length + (ending as NSString).length, length: 0)]
        )
    }

    private static func outdentAmount(for whitespace: String, options: IndentationOptions) -> Int {
        if options.usesTabs {
            if let tabIndex = whitespace.firstIndex(of: "\t") {
                return whitespace.distance(from: whitespace.startIndex, to: tabIndex) + 1
            }
            return min(whitespace.count, options.tabWidth)
        }
        return min(whitespace.count, options.tabWidth)
    }

    private static func convertIndent(
        text: String,
        selection: NSRange,
        toTabs: Bool,
        tabWidth: Int
    ) -> EditorCommandResult {
        let lines = EditorTextSupport.affectedLineRanges(for: selection, in: text)
        var edits: [TextEdit] = []
        for line in lines {
            let wsLength = EditorTextSupport.leadingWhitespaceLength(on: line, in: text)
            guard wsLength > 0 else { continue }
            let ws = EditorTextSupport.leadingWhitespace(on: line, in: text)
            let column = EditorTextSupport.visualColumn(
                of: line.location + wsLength,
                in: text,
                tabWidth: tabWidth
            )
            let newWS: String
            if toTabs {
                let tabs = column / tabWidth
                let spaces = column % tabWidth
                newWS = String(repeating: "\t", count: tabs) + String(repeating: " ", count: spaces)
            } else {
                newWS = String(repeating: " ", count: column)
            }
            guard newWS != ws else { continue }
            edits.append(TextEdit(
                range: NSRange(location: line.location, length: wsLength),
                replacement: newWS
            ))
        }
        return EditorCommandResult(edits: edits, resultingSelections: [selection])
    }
}
