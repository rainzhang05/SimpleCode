import Foundation

enum SmartHomeEngine {
    /// `isSecondPress` is true when Home was already pressed once on this line without moving.
    static func home(
        text: String,
        selection: NSRange,
        isSecondPress: Bool,
        tabWidth: Int = 4,
        extendSelection: Bool = false
    ) -> EditorCommandResult {
        let anchor = selection.location
        let line = EditorTextSupport.lineRange(at: anchor, in: text)
        let firstNonWS = EditorTextSupport.firstNonWhitespaceOffset(on: line, in: text)
        let lineStart = line.location

        let target: Int
        if isSecondPress {
            target = lineStart
        } else if anchor == lineStart {
            target = lineStart
        } else {
            target = firstNonWS
        }

        let resultingSelection: NSRange
        if extendSelection {
            let fixedEnd = selection.length == 0 ? anchor : NSMaxRange(selection)
            resultingSelection = NSRange(
                location: min(target, fixedEnd),
                length: abs(fixedEnd - target)
            )
        } else {
            resultingSelection = NSRange(location: target, length: 0)
        }

        return EditorCommandResult(
            edits: [],
            resultingSelections: [resultingSelection]
        )
    }
}
