import Foundation
import Testing
@testable import SimpleCode

struct BracketMatcherTests {
    @Test func matchesParentheses() {
        let text = "(hello)"
        let open = (text as NSString).range(of: "(").location
        let close = (text as NSString).range(of: ")").location
        #expect(BracketMatcher.matchingBracket(at: open, in: text) == close)
        #expect(BracketMatcher.matchingBracket(at: close, in: text) == open)
    }

    @Test func matchesNestedBraces() {
        let text = "f({})"
        let outerOpen = (text as NSString).range(of: "{").location
        let outerClose = (text as NSString).range(of: "}").location
        #expect(BracketMatcher.matchingBracket(at: outerOpen, in: text) == outerClose)
    }

    @Test func skipsBracketsInsideStrings() {
        let text = "\"(not a bracket)\""
        let parenInString = (text as NSString).range(of: "(").location
        let ctx = SyntaxContext(stringRanges: [NSRange(location: 0, length: (text as NSString).length)], commentRanges: [])
        #expect(BracketMatcher.matchingBracket(at: parenInString, in: text, syntaxContext: ctx) == nil)
    }

    @Test func skipsBracketsInsideComments() {
        let text = "code // (comment)"
        let parenInComment = (text as NSString).range(of: "(").location
        let commentStart = (text as NSString).range(of: "//").location
        let ctx = SyntaxContext(stringRanges: [], commentRanges: [NSRange(location: commentStart, length: 11)])
        #expect(BracketMatcher.matchingBracket(at: parenInComment, in: text, syntaxContext: ctx) == nil)
    }

    @Test func noMatchForMismatched() {
        let text = "(]"
        let open = (text as NSString).range(of: "(").location
        #expect(BracketMatcher.matchingBracket(at: open, in: text) == nil)
    }

    @Test func boundedScanReturnsNilWhenTooFar() {
        let padding = String(repeating: " ", count: 50)
        let text = "(\(padding))"
        let open = (text as NSString).range(of: "(").location
        #expect(BracketMatcher.matchingBracket(at: open, in: text, scanBound: 10) == nil)
    }

    @Test func matchesSquareBrackets() {
        let text = "[a[b]c]"
        let outerOpen = 0
        let outerClose = (text as NSString).length - 1
        #expect(BracketMatcher.matchingBracket(at: outerOpen, in: text) == outerClose)
    }

    @Test func angleBracketsAreNotMatchedWithoutLanguageContext() {
        let text = "<T>"
        #expect(BracketMatcher.matchingBracket(at: 0, in: text) == nil)
        #expect(BracketMatcher.matchingBracket(at: 2, in: text) == nil)
    }
}
