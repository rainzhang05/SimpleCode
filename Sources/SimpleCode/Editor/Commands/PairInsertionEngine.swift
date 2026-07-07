import Foundation

enum PairInsertionEngine {
    private static let openToClose: [Character: Character] = [
        "(": ")",
        "[": "]",
        "{": "}",
        "\"": "\"",
        "'": "'",
        "`": "`",
    ]

    static func insert(
        character: Character,
        text: String,
        selection: NSRange,
        syntaxContext: SyntaxContext? = nil
    ) -> EditorCommandResult? {
        guard let closer = openToClose[character] else { return nil }

        if character == "\"" || character == "'" || character == "`" {
            guard shouldInsertQuote(character, at: selection.location, in: text, syntaxContext: syntaxContext) else {
                return nil
            }
        }

        let open = String(character)
        let close = String(closer)

        if selection.length > 0 {
            let selectedText = EditorTextSupport.substring(selection, in: text)
            return wrapSelection(open: open, close: close, selection: selection, selectedText: selectedText)
        }

        if let skip = skipOverExistingCloser(close, at: selection.location, in: text) {
            return skip
        }

        let insertion = open + close
        let edit = TextEdit(range: NSRange(location: selection.location, length: 0), replacement: insertion)
        return EditorCommandResult(
            edits: [edit],
            resultingSelections: [NSRange(location: selection.location + 1, length: 0)]
        )
    }

    private static func wrapSelection(
        open: String,
        close: String,
        selection: NSRange,
        selectedText: String
    ) -> EditorCommandResult {
        let edit = TextEdit(
            range: selection,
            replacement: open + selectedText + close
        )
        let innerStart = selection.location + (open as NSString).length
        return EditorCommandResult(
            edits: [edit],
            resultingSelections: [NSRange(location: innerStart, length: selection.length)]
        )
    }

    private static func skipOverExistingCloser(
        _ closer: String,
        at location: Int,
        in text: String
    ) -> EditorCommandResult? {
        let ns = EditorTextSupport.nsString(text)
        guard location < ns.length else { return nil }
        let closeChar = closer.utf16.first.map { UInt16($0) } ?? 0
        guard ns.character(at: location) == closeChar else { return nil }
        return EditorCommandResult(
            edits: [],
            resultingSelections: [NSRange(location: location + 1, length: 0)]
        )
    }

    private static func shouldInsertQuote(
        _ quote: Character,
        at location: Int,
        in text: String,
        syntaxContext: SyntaxContext?
    ) -> Bool {
        if let ctx = syntaxContext, ctx.isInsideSpecialToken(at: location) {
            return false
        }
        return !isInWordContext(at: location, in: text, quote: quote)
    }

    private static func isInWordContext(at location: Int, in text: String, quote: Character) -> Bool {
        let ns = EditorTextSupport.nsString(text)
        if location > 0 {
            let prev = ns.character(at: location - 1)
            if isWordCharacter(prev) { return true }
        }
        if location < ns.length {
            let next = ns.character(at: location)
            if isWordCharacter(next) { return true }
        }
        return false
    }

    private static func isWordCharacter(_ codeUnit: UInt16) -> Bool {
        guard let scalar = UnicodeScalar(codeUnit) else { return false }
        return CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
    }
}
