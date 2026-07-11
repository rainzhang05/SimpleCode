import Foundation

enum SmartBackspaceEngine {
    static func backspace(
        text: String,
        selection: NSRange,
        tabWidth: Int,
        smartPairDeletionEnabled: Bool
    ) -> EditorCommandResult? {
        guard selection.length == 0 else { return nil }
        let location = selection.location
        guard location > 0 else { return nil }

        if smartPairDeletionEnabled,
           let pairEdit = emptyPairDeletion(at: location, in: text) {
            return pairEdit
        }

        if let tabStopEdit = tabStopDeletion(at: location, in: text, tabWidth: tabWidth) {
            return tabStopEdit
        }

        // Let NSTextView delete ordinary text. It understands composed-character
        // sequences, surrogate pairs, CRLF, IME composition, and native undo.
        return nil
    }

    private static func tabStopDeletion(
        at location: Int,
        in text: String,
        tabWidth: Int
    ) -> EditorCommandResult? {
        guard location > 0 else { return nil }
        let ns = EditorTextSupport.nsString(text)
        let lineStart = EditorTextSupport.lineStart(at: location, in: text)
        let before = ns.substring(with: NSRange(location: lineStart, length: location - lineStart))

        guard !before.isEmpty else { return nil }
        guard before.allSatisfy({ $0 == " " || $0 == "\t" }) else { return nil }

        let column = EditorTextSupport.visualColumn(of: location, in: text, tabWidth: tabWidth)
        guard column > 0 else { return nil }

        let prevTabColumn = ((column - 1) / tabWidth) * tabWidth
        let targetLocation = EditorTextSupport.locationForVisualColumn(
            prevTabColumn,
            onLineStartingAt: lineStart,
            in: text,
            tabWidth: tabWidth
        )
        guard targetLocation < location else { return nil }

        let edit = TextEdit(
            range: NSRange(location: targetLocation, length: location - targetLocation),
            replacement: ""
        )
        return EditorCommandResult(
            edits: [edit],
            resultingSelections: [NSRange(location: targetLocation, length: 0)]
        )
    }

    private static func emptyPairDeletion(at location: Int, in text: String) -> EditorCommandResult? {
        let ns = EditorTextSupport.nsString(text)
        guard location > 0, location < ns.length else { return nil }

        let pairs: [(UInt16, UInt16)] = [
            (40, 41),   // ()
            (91, 93),   // []
            (123, 125), // {}
            (34, 34),   // ""
            (39, 39),   // ''
            (96, 96),   // ``
        ]

        let open = ns.character(at: location - 1)
        let close = ns.character(at: location)

        guard pairs.contains(where: { $0.0 == open && $0.1 == close }) else { return nil }

        let edit = TextEdit(
            range: NSRange(location: location - 1, length: 2),
            replacement: ""
        )
        return EditorCommandResult(
            edits: [edit],
            resultingSelections: [NSRange(location: location - 1, length: 0)]
        )
    }
}
