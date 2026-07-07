import Foundation

struct EditorCommandController: Sendable {
    var indentationOptions: IndentationOptions
    var tabWidth: Int
    var smartPairDeletionEnabled: Bool

    init(
        indentationOptions: IndentationOptions = IndentationOptions(language: .swift),
        tabWidth: Int = 4,
        smartPairDeletionEnabled: Bool = true
    ) {
        self.indentationOptions = indentationOptions
        self.tabWidth = tabWidth
        self.smartPairDeletionEnabled = smartPairDeletionEnabled
    }

    func returnKey(text: String, cursorLocation: Int) -> EditorCommandResult {
        IndentationEngine.returnKey(text: text, cursorLocation: cursorLocation, options: indentationOptions)
    }

    func backspace(text: String, selection: NSRange) -> EditorCommandResult? {
        SmartBackspaceEngine.backspace(
            text: text,
            selection: selection,
            tabWidth: tabWidth,
            smartPairDeletionEnabled: smartPairDeletionEnabled
        )
    }

    func home(text: String, selection: NSRange, isSecondPress: Bool, extendSelection: Bool = false) -> EditorCommandResult {
        SmartHomeEngine.home(
            text: text,
            selection: selection,
            isSecondPress: isSecondPress,
            tabWidth: tabWidth,
            extendSelection: extendSelection
        )
    }

    func insertPair(
        character: Character,
        text: String,
        selection: NSRange,
        syntaxContext: SyntaxContext? = nil
    ) -> EditorCommandResult? {
        PairInsertionEngine.insert(
            character: character,
            text: text,
            selection: selection,
            syntaxContext: syntaxContext
        )
    }

    func toggleComment(text: String, selection: NSRange) -> EditorCommandResult? {
        CommentToggleEngine.toggle(text: text, selection: selection, language: indentationOptions.language)
    }

    func duplicateLine(text: String, selection: NSRange) -> EditorCommandResult {
        LineCommandEngine.duplicateLine(text: text, selection: selection)
    }

    func moveLineUp(text: String, selection: NSRange) -> EditorCommandResult? {
        LineCommandEngine.moveLineUp(text: text, selection: selection)
    }

    func moveLineDown(text: String, selection: NSRange) -> EditorCommandResult? {
        LineCommandEngine.moveLineDown(text: text, selection: selection)
    }

    func deleteLine(text: String, selection: NSRange) -> EditorCommandResult {
        LineCommandEngine.deleteLine(text: text, selection: selection)
    }

    func indent(text: String, selection: NSRange) -> EditorCommandResult {
        LineCommandEngine.indent(text: text, selection: selection, options: indentationOptions)
    }

    func outdent(text: String, selection: NSRange) -> EditorCommandResult {
        LineCommandEngine.outdent(text: text, selection: selection, options: indentationOptions)
    }

    func convertIndentToSpaces(text: String, selection: NSRange) -> EditorCommandResult {
        LineCommandEngine.convertIndentToSpaces(text: text, selection: selection, tabWidth: tabWidth)
    }

    func convertIndentToTabs(text: String, selection: NSRange) -> EditorCommandResult {
        LineCommandEngine.convertIndentToTabs(text: text, selection: selection, tabWidth: tabWidth)
    }

    func trimTrailingWhitespace(text: String, selection: NSRange) -> EditorCommandResult {
        LineCommandEngine.trimTrailingWhitespace(text: text, selection: selection)
    }

    func insertFinalNewline(text: String) -> EditorCommandResult? {
        LineCommandEngine.insertFinalNewline(text: text)
    }

    func matchingBracket(
        at location: Int,
        in text: String,
        syntaxContext: SyntaxContext? = nil
    ) -> Int? {
        BracketMatcher.matchingBracket(at: location, in: text, syntaxContext: syntaxContext)
    }

    /// Applies edits from end to start and returns the resulting text.
    func apply(_ result: EditorCommandResult, to text: String) -> String {
        EditorTextSupport.applyEdits(result.edits, to: text)
    }
}
