import Foundation
import Testing
@testable import SimpleCode

struct SmartBackspaceEngineTests {
    private func apply(_ result: EditorCommandResult, to text: String) -> String {
        EditorTextSupport.applyEdits(result.edits, to: text)
    }

    @Test func deletesSingleCharacter() {
        let text = "abc"
        let sel = NSRange(location: 3, length: 0)
        let result = SmartBackspaceEngine.backspace(text: text, selection: sel, tabWidth: 4, smartPairDeletionEnabled: false)!
        let output = apply(result, to: text)
        #expect(output == "ab")
        #expect(result.resultingSelections == [NSRange(location: 2, length: 0)])
    }

    @Test func tabStopDeletionWithSpaces() {
        let text = "        x"
        let sel = NSRange(location: 8, length: 0)
        let result = SmartBackspaceEngine.backspace(text: text, selection: sel, tabWidth: 4, smartPairDeletionEnabled: false)!
        let output = apply(result, to: text)
        #expect(output == "    x")
        #expect(result.resultingSelections == [NSRange(location: 4, length: 0)])
    }

    @Test func tabStopDeletionWithTab() {
        let text = "\t\tx"
        let sel = NSRange(location: 2, length: 0)
        let result = SmartBackspaceEngine.backspace(text: text, selection: sel, tabWidth: 4, smartPairDeletionEnabled: false)!
        let output = apply(result, to: text)
        #expect(output == "\tx")
    }

    @Test func emptyPairDeletion() {
        let text = "()"
        let sel = NSRange(location: 1, length: 0)
        let result = SmartBackspaceEngine.backspace(text: text, selection: sel, tabWidth: 4, smartPairDeletionEnabled: true)!
        let output = apply(result, to: text)
        #expect(output == "")
    }

    @Test func emptyBracePairDeletion() {
        let text = "{}"
        let sel = NSRange(location: 1, length: 0)
        let result = SmartBackspaceEngine.backspace(text: text, selection: sel, tabWidth: 4, smartPairDeletionEnabled: true)!
        #expect(apply(result, to: text) == "")
    }

    @Test func emptyQuotePairDeletion() {
        let text = "\"\""
        let sel = NSRange(location: 1, length: 0)
        let result = SmartBackspaceEngine.backspace(text: text, selection: sel, tabWidth: 4, smartPairDeletionEnabled: true)!
        #expect(apply(result, to: text) == "")
    }

    @Test func noOpAtStart() {
        let text = "a"
        let sel = NSRange(location: 0, length: 0)
        let result = SmartBackspaceEngine.backspace(text: text, selection: sel, tabWidth: 4, smartPairDeletionEnabled: true)
        #expect(result == nil)
    }
}
