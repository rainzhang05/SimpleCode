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
        let edit = TextEdit(
            range: NSRange(location: lastLine.location + lastLine.length, length: 0),
            replacement: lineText
        )
        let newCursor = lastLine.location + lastLine.length + (lineText as NSString).length
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
        guard let first = lines.first else { return nil }
        guard first.location > 0 else { return nil }

        let ns = EditorTextSupport.nsString(text)
        let prevLine = ns.lineRange(for: NSRange(location: first.location - 1, length: 0))
        let block = ns.substring(with: NSRange(
            location: first.location,
            length: lines.last!.location + lines.last!.length - first.location
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
        guard let last = lines.last else { return nil }
        let ns = EditorTextSupport.nsString(text)
        let blockEnd = last.location + last.length
        guard blockEnd < ns.length else { return nil }

        let nextLine = ns.lineRange(for: NSRange(location: blockEnd, length: 0))
        let first = lines.first!
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
        let lines = EditorTextSupport.affectedLineRanges(for: selection, in: text)
        let unit = options.indentUnit
        var edits: [TextEdit] = []
        for line in lines {
            let insertAt = EditorTextSupport.firstNonWhitespaceOffset(on: line, in: text)
            edits.append(TextEdit(range: NSRange(location: insertAt, length: 0), replacement: unit))
        }
        let delta = (unit as NSString).length
        let newLocation = selection.location + delta
        return EditorCommandResult(
            edits: edits,
            resultingSelections: [NSRange(location: newLocation, length: selection.length)]
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

        let newLocation = max(0, selection.location - totalRemovedBeforeSelection)
        return EditorCommandResult(
            edits: edits,
            resultingSelections: [NSRange(location: newLocation, length: selection.length)]
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
