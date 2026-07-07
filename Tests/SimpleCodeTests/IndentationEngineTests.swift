import Foundation
import Testing
@testable import SimpleCode

struct IndentationEngineTests {
    private func apply(_ result: EditorCommandResult, to text: String) -> String {
        EditorTextSupport.applyEdits(result.edits, to: text)
    }

    @Test func preserveIndentOnReturn() {
        let text = "    hello"
        let options = IndentationOptions(language: .swift, usesTabs: false, tabWidth: 4)
        let result = IndentationEngine.returnKey(text: text, cursorLocation: 9, options: options)
        let output = apply(result, to: text)
        #expect(output == "    hello\n    ")
        #expect(result.resultingSelections == [NSRange(location: 14, length: 0)])
    }

    @Test func braceBlockIncreasesIndent() {
        let text = "func foo() {"
        let options = IndentationOptions(language: .swift, usesTabs: false, tabWidth: 4)
        let result = IndentationEngine.returnKey(text: text, cursorLocation: text.utf16.count, options: options)
        let output = apply(result, to: text)
        #expect(output == "func foo() {\n    ")
    }

    @Test func pairAwareReturnBetweenBraces() {
        let text = "func foo() {}"
        let cursor = (text as NSString).range(of: "{").location + 1
        let options = IndentationOptions(language: .swift, usesTabs: false, tabWidth: 4)
        let result = IndentationEngine.returnKey(text: text, cursorLocation: cursor, options: options)
        let output = apply(result, to: text)
        #expect(output.contains("{\n    \n}"))
        #expect(result.resultingSelections.first?.location == cursor + 1 + 4)
    }

    @Test func pairAwareReturnBetweenParenthesesAndBrackets() {
        let options = IndentationOptions(language: .swift, usesTabs: false, tabWidth: 4)

        let call = "foo()"
        let callCursor = (call as NSString).range(of: "(").location + 1
        let callResult = IndentationEngine.returnKey(text: call, cursorLocation: callCursor, options: options)
        #expect(apply(callResult, to: call) == "foo(\n    \n)")

        let list = "let xs = []"
        let listCursor = (list as NSString).range(of: "[").location + 1
        let listResult = IndentationEngine.returnKey(text: list, cursorLocation: listCursor, options: options)
        #expect(apply(listResult, to: list) == "let xs = [\n    \n]")
    }

    @Test func dedentOnClosingBrace() {
        let text = "    }"
        let options = IndentationOptions(language: .swift, usesTabs: false, tabWidth: 4)
        let result = IndentationEngine.returnKey(text: text, cursorLocation: 5, options: options)
        let output = apply(result, to: text)
        #expect(output == "    }\n")
    }

    @Test func dedentClosingBracket() {
        let text = "        ]"
        let options = IndentationOptions(language: .swift, usesTabs: false, tabWidth: 4)
        let result = IndentationEngine.returnKey(text: text, cursorLocation: 9, options: options)
        let output = apply(result, to: text)
        #expect(output.hasSuffix("\n    "))
    }

    @Test func pythonColonIndent() {
        let text = "if True:"
        let options = IndentationOptions(language: .python, usesTabs: false, tabWidth: 4)
        let result = IndentationEngine.returnKey(text: text, cursorLocation: text.utf16.count, options: options)
        let output = apply(result, to: text)
        #expect(output == "if True:\n    ")
    }

    @Test func pythonLambdaColonDoesNotIndentAsBlockHeader() {
        let text = "handler = lambda value:"
        let options = IndentationOptions(language: .python, usesTabs: false, tabWidth: 4)
        let result = IndentationEngine.returnKey(text: text, cursorLocation: text.utf16.count, options: options)
        let output = apply(result, to: text)
        #expect(output == "handler = lambda value:\n")
    }

    @Test func pythonDedentKeywords() {
        let text = "        return"
        let options = IndentationOptions(language: .python, usesTabs: false, tabWidth: 4)
        let result = IndentationEngine.returnKey(text: text, cursorLocation: text.utf16.count, options: options)
        let output = apply(result, to: text)
        #expect(output == "        return\n    ")
    }

    @Test func shellThenIndent() {
        let text = "if [ -f foo ]; then"
        let options = IndentationOptions(language: .shell, usesTabs: false, tabWidth: 4)
        let result = IndentationEngine.returnKey(text: text, cursorLocation: text.utf16.count, options: options)
        let output = apply(result, to: text)
        #expect(output.hasSuffix("then\n    "))
    }

    @Test func shellWordsInsideCommandsDoNotTriggerIndentOrDedent() {
        let options = IndentationOptions(language: .shell, usesTabs: false, tabWidth: 4)

        let thenText = "echo then"
        let thenResult = IndentationEngine.returnKey(text: thenText, cursorLocation: thenText.utf16.count, options: options)
        #expect(apply(thenResult, to: thenText) == "echo then\n")

        let doneText = "    echo done"
        let doneResult = IndentationEngine.returnKey(text: doneText, cursorLocation: doneText.utf16.count, options: options)
        #expect(apply(doneResult, to: doneText) == "    echo done\n    ")
    }

    @Test func shellFiDedent() {
        let text = "    fi"
        let options = IndentationOptions(language: .shell, usesTabs: false, tabWidth: 4)
        let result = IndentationEngine.returnKey(text: text, cursorLocation: text.utf16.count, options: options)
        let output = apply(result, to: text)
        #expect(output == "    fi\n")
    }

    @Test func makefileUsesTabs() {
        let text = "target:"
        let options = IndentationOptions(language: .makefile)
        #expect(options.usesTabs == true)
        let result = IndentationEngine.returnKey(text: text, cursorLocation: text.utf16.count, options: options)
        let output = apply(result, to: text)
        #expect(output == "target:\n\t")
    }

    @Test func tabIndentPreserved() {
        let text = "\thello"
        let options = IndentationOptions(language: .swift, usesTabs: true, tabWidth: 4)
        let result = IndentationEngine.returnKey(text: text, cursorLocation: text.utf16.count, options: options)
        let output = apply(result, to: text)
        #expect(output == "\thello\n\t")
    }
}
