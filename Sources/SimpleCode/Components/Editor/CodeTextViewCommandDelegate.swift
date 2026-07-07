import AppKit

@MainActor
protocol CodeTextViewCommandDelegate: AnyObject {
    func codeTextViewHandleReturn(_ textView: CodeTextView) -> Bool
    func codeTextViewHandleTab(_ textView: CodeTextView, shift: Bool) -> Bool
    func codeTextViewHandleDeleteBackward(_ textView: CodeTextView) -> Bool
    func codeTextViewHandleMoveToBeginningOfLine(_ textView: CodeTextView, extendSelection: Bool) -> Bool
    func codeTextView(_ textView: CodeTextView, shouldInsertCharacter character: Character) -> Bool
}
