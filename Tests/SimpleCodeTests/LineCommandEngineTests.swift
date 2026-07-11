import Foundation
import Testing
@testable import SimpleCode

struct LineCommandEngineTests {
    private let options = IndentationOptions(language: .swift, usesTabs: false, tabWidth: 4)

    private func apply(_ result: EditorCommandResult, to text: String) -> String {
        EditorTextSupport.applyEdits(result.edits, to: text)
    }

    @Test func duplicateFinalUnterminatedLineInsertsASeparator() {
        let text = "line1\nline2"
        let sel = NSRange(location: 6, length: 0)
        let result = LineCommandEngine.duplicateLine(text: text, selection: sel)
        let output = apply(result, to: text)
        #expect(output == "line1\nline2\nline2")
    }

    @Test func moveLineUp() {
        let text = "a\nb\nc"
        let sel = NSRange(location: 2, length: 1)
        let result = LineCommandEngine.moveLineUp(text: text, selection: sel)!
        let output = apply(result, to: text)
        #expect(output == "b\na\nc")
    }

    @Test func moveLineDown() {
        let text = "a\nb\nc"
        let sel = NSRange(location: 0, length: 1)
        let result = LineCommandEngine.moveLineDown(text: text, selection: sel)!
        let output = apply(result, to: text)
        #expect(output == "b\na\nc")
    }

    @Test func deleteLine() {
        let text = "a\nb\nc"
        let sel = NSRange(location: 2, length: 0)
        let result = LineCommandEngine.deleteLine(text: text, selection: sel)
        let output = apply(result, to: text)
        #expect(output == "a\nc")
    }

    @Test func indentSelection() {
        let text = "a\nb"
        let sel = NSRange(location: 0, length: (text as NSString).length)
        let result = LineCommandEngine.indent(text: text, selection: sel, options: options)
        let output = apply(result, to: text)
        #expect(output == "    a\n    b")
        #expect(result.resultingSelections == [NSRange(location: 0, length: 11)])
    }

    @Test func outdentSelection() {
        let text = "    a\n    b"
        let sel = NSRange(location: 0, length: (text as NSString).length)
        let result = LineCommandEngine.outdent(text: text, selection: sel, options: options)
        let output = apply(result, to: text)
        #expect(output == "a\nb")
        #expect(result.resultingSelections == [NSRange(location: 0, length: 3)])
    }

    @Test func indentAtACollapsedCaretMovesToTheNextVisualTabStop() {
        let text = "  value"
        let result = LineCommandEngine.indent(
            text: text,
            selection: NSRange(location: 2, length: 0),
            options: options
        )

        #expect(apply(result, to: text) == "    value")
        #expect(result.resultingSelections == [NSRange(location: 4, length: 0)])
    }

    @Test func convertIndentToSpaces() {
        let text = "\ta"
        let sel = NSRange(location: 0, length: (text as NSString).length)
        let result = LineCommandEngine.convertIndentToSpaces(text: text, selection: sel, tabWidth: 4)
        let output = apply(result, to: text)
        #expect(output == "    a")
    }

    @Test func convertIndentToTabs() {
        let text = "    a"
        let sel = NSRange(location: 0, length: (text as NSString).length)
        let result = LineCommandEngine.convertIndentToTabs(text: text, selection: sel, tabWidth: 4)
        let output = apply(result, to: text)
        #expect(output == "\ta")
    }

    @Test func trimTrailingWhitespace() {
        let text = "hello   \nworld\t"
        let sel = NSRange(location: 0, length: (text as NSString).length)
        let result = LineCommandEngine.trimTrailingWhitespace(text: text, selection: sel)
        let output = apply(result, to: text)
        #expect(output == "hello\nworld")
    }

    @Test func trimTrailingWhitespacePreservesCRLFLineEndings() {
        let text = "hello   \r\nworld\t\r\n"
        let selection = NSRange(location: 0, length: (text as NSString).length)

        let result = LineCommandEngine.trimTrailingWhitespace(text: text, selection: selection)

        #expect(apply(result, to: text) == "hello\r\nworld\r\n")
    }

    @Test func insertFinalNewline() {
        let text = "no newline"
        let result = LineCommandEngine.insertFinalNewline(text: text)!
        let output = apply(result, to: text)
        #expect(output == "no newline\n")
    }

    @Test func insertFinalNewlineSkipsWhenPresent() {
        let text = "has newline\n"
        let result = LineCommandEngine.insertFinalNewline(text: text)
        #expect(result == nil)
    }
}
