import Foundation
import Testing
@testable import SimpleCode

struct CommentToggleEngineTests {
    private func apply(_ result: EditorCommandResult, to text: String) -> String {
        EditorTextSupport.applyEdits(result.edits, to: text)
    }

    @Test func swiftLineComment() {
        let text = "let x = 1"
        let sel = NSRange(location: 0, length: text.utf16.count)
        let result = CommentToggleEngine.toggle(text: text, selection: sel, language: .swift)!
        let output = apply(result, to: text)
        #expect(output == "// let x = 1")
    }

    @Test func pythonHashComment() {
        let text = "print('hi')"
        let sel = NSRange(location: 0, length: text.utf16.count)
        let result = CommentToggleEngine.toggle(text: text, selection: sel, language: .python)!
        let output = apply(result, to: text)
        #expect(output == "# print('hi')")
    }

    @Test func uncommentLines() {
        let text = "// let x = 1\n// let y = 2"
        let sel = NSRange(location: 0, length: (text as NSString).length)
        let result = CommentToggleEngine.toggle(text: text, selection: sel, language: .swift)!
        let output = apply(result, to: text)
        #expect(output == "let x = 1\nlet y = 2")
    }

    @Test func multiLineSelection() {
        let text = "a\nb\nc"
        let sel = NSRange(location: 0, length: (text as NSString).length)
        let result = CommentToggleEngine.toggle(text: text, selection: sel, language: .swift)!
        let output = apply(result, to: text)
        #expect(output == "// a\n// b\n// c")
    }

    @Test func blankLinesSkippedWhenOtherLinesPresent() {
        let text = "a\n\nb"
        let sel = NSRange(location: 0, length: (text as NSString).length)
        let result = CommentToggleEngine.toggle(text: text, selection: sel, language: .swift)!
        let output = apply(result, to: text)
        #expect(output == "// a\n\n// b")
    }

    @Test func plainTextReturnsNil() {
        let text = "hello"
        let sel = NSRange(location: 0, length: 5)
        let result = CommentToggleEngine.toggle(text: text, selection: sel, language: .plainText)
        #expect(result == nil)
    }
}
