import AppKit

@MainActor
protocol CodeTextViewCommandDelegate: AnyObject {
    func codeTextViewHandleReturn(_ textView: CodeTextView) -> Bool
    func codeTextViewHandleTab(_ textView: CodeTextView, shift: Bool) -> Bool
    func codeTextViewHandleDeleteBackward(_ textView: CodeTextView) -> Bool
    func codeTextViewHandleMoveToBeginningOfLine(_ textView: CodeTextView, extendSelection: Bool) -> Bool
    func codeTextView(_ textView: CodeTextView, shouldInsertCharacter character: Character) -> Bool
}

/// Routes commands initiated outside the NSTextView (menu actions, Find/Replace,
/// and workspace shortcuts) through the currently attached native text surface.
/// That preserves AppKit selection, undo, and input-method semantics.
@MainActor
protocol EditorTextMutationApplying: AnyObject {
    func applyEditorMutation(_ result: EditorCommandResult, to session: EditorDocumentSession) -> Bool
}
