import Foundation
import Testing
@testable import SimpleCode

struct LineCountingTests {
    @Test func offsetZeroIsAlwaysLineOne() {
        #expect(LineCounting.lineNumber(atUTF16Offset: 0, in: "anything\nhere") == 1)
    }

    @Test func offsetOnTheFirstLineIsLineOne() {
        let text = "hello\nworld"
        #expect(LineCounting.lineNumber(atUTF16Offset: 3, in: text) == 1)
    }

    @Test func offsetJustAfterANewlineIsTheNextLine() {
        let text = "hello\nworld"
        let newlineOffset = (text as NSString).range(of: "\n").location
        #expect(LineCounting.lineNumber(atUTF16Offset: newlineOffset + 1, in: text) == 2)
    }

    @Test func countsMultipleLinesCorrectly() {
        let text = "one\ntwo\nthree\nfour"
        let offsetOfFour = (text as NSString).range(of: "four").location
        #expect(LineCounting.lineNumber(atUTF16Offset: offsetOfFour, in: text) == 4)
    }

    @Test func offsetBeyondTheEndOfTextClampsRatherThanCrashing() {
        let text = "short"
        #expect(LineCounting.lineNumber(atUTF16Offset: 999, in: text) == 1)
    }

    @Test func emptyTextReturnsLineOne() {
        #expect(LineCounting.lineNumber(atUTF16Offset: 0, in: "") == 1)
    }

    @Test func lineStartOffsetForFirstLineIsZero() {
        #expect(LineCounting.lineStartUTF16Offset(forLine: 1, in: "a\nb") == 0)
    }

    @Test func lineStartOffsetForLaterLines() {
        let text = "hello\nworld"
        #expect(LineCounting.lineStartUTF16Offset(forLine: 2, in: text) == 6)
    }
}
