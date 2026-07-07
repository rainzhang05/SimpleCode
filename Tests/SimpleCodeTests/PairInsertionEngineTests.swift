import Foundation
import Testing
@testable import SimpleCode

struct PairInsertionEngineTests {
    private func apply(_ result: EditorCommandResult, to text: String) -> String {
        EditorTextSupport.applyEdits(result.edits, to: text)
    }

    @Test func insertsParenthesesPair() {
        let text = "foo"
        let sel = NSRange(location: 3, length: 0)
        let result = PairInsertionEngine.insert(character: "(", text: text, selection: sel)!
        let output = apply(result, to: text)
        #expect(output == "foo()")
        #expect(result.resultingSelections == [NSRange(location: 4, length: 0)])
    }

    @Test func wrapsSelection() {
        let text = "hello"
        let sel = NSRange(location: 0, length: 5)
        let result = PairInsertionEngine.insert(character: "(", text: text, selection: sel)!
        let output = apply(result, to: text)
        #expect(output == "(hello)")
        #expect(result.resultingSelections == [NSRange(location: 1, length: 5)])
    }

    @Test func skipsExistingCloser() {
        let text = "foo)"
        let sel = NSRange(location: 3, length: 0)
        let result = PairInsertionEngine.insert(character: "(", text: text, selection: sel)!
        #expect(result.edits.isEmpty)
        #expect(result.resultingSelections == [NSRange(location: 4, length: 0)])
    }

    @Test func avoidsQuoteInWordContext() {
        let text = "don"
        let sel = NSRange(location: 3, length: 0)
        let result = PairInsertionEngine.insert(character: "\"", text: text, selection: sel)
        #expect(result == nil)
    }

    @Test func insertsQuoteWhenNotInWordContext() {
        let text = "foo "
        let sel = NSRange(location: 4, length: 0)
        let result = PairInsertionEngine.insert(character: "\"", text: text, selection: sel)!
        let output = apply(result, to: text)
        #expect(output == "foo \"\"")
    }

    @Test func respectsSyntaxContextForQuotes() {
        let text = "let x = value"
        let sel = NSRange(location: 13, length: 0)
        let ctx = SyntaxContext(stringRanges: [NSRange(location: 8, length: 5)], commentRanges: [])
        let result = PairInsertionEngine.insert(character: "\"", text: text, selection: sel, syntaxContext: ctx)
        #expect(result == nil)
    }

    @Test func insertsBracketsAndBraces() {
        let text = ""
        #expect(apply(PairInsertionEngine.insert(character: "[", text: text, selection: NSRange(location: 0, length: 0))!, to: text) == "[]")
        #expect(apply(PairInsertionEngine.insert(character: "{", text: text, selection: NSRange(location: 0, length: 0))!, to: text) == "{}")
    }

    @Test func rejectsBackticksInWordContext() {
        let text = "cmd"
        let sel = NSRange(location: 3, length: 0)
        let result = PairInsertionEngine.insert(character: "`", text: text, selection: sel)
        #expect(result == nil)
    }

    @Test func insertsBackticksAfterWhitespace() {
        let text = "cmd "
        let sel = NSRange(location: 4, length: 0)
        let result = PairInsertionEngine.insert(character: "`", text: text, selection: sel)!
        #expect(apply(result, to: text) == "cmd ``")
    }

    @Test func angleBracketPairingStaysDisabled() {
        let text = "a < "
        let sel = NSRange(location: 4, length: 0)
        let result = PairInsertionEngine.insert(character: "<", text: text, selection: sel)
        #expect(result == nil)
    }
}
