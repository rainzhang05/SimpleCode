import Foundation
import Testing
@testable import SimpleCode

struct LineStartIndexTests {
    @Test func emptyDocumentHasOneLine() {
        var index = LineStartIndex()
        index.rebuild(from: "")
        #expect(index.lineCount == 1)
        #expect(index.lineNumber(atUTF16Offset: 0) == 1)
    }

    @Test func singleLineDocument() {
        var index = LineStartIndex()
        index.rebuild(from: "hello")
        #expect(index.lineCount == 1)
        #expect(index.lineNumber(atUTF16Offset: 3) == 1)
        #expect(index.lineStartUTF16Offset(forLine: 1) == 0)
    }

    @Test func multilineLFDocument() {
        var index = LineStartIndex()
        index.rebuild(from: "a\nb\nc")
        #expect(index.lineCount == 3)
        #expect(index.lineNumber(atUTF16Offset: 0) == 1)
        #expect(index.lineNumber(atUTF16Offset: 2) == 2)
        #expect(index.lineNumber(atUTF16Offset: 4) == 3)
    }

    @Test func crlfLineBreaks() {
        var index = LineStartIndex()
        index.rebuild(from: "a\r\nb")
        #expect(index.lineCount == 2)
        #expect(index.lineNumber(atUTF16Offset: 3) == 2)
    }

    @Test func incrementalInsertCreatesNewLine() {
        var index = LineStartIndex()
        index.rebuild(from: "ab")
        index.applyEdit(
            editedRange: NSRange(location: 2, length: 0),
            changeInLength: 1,
            insertedText: "\n",
            fullText: "ab\n"
        )
        #expect(index.lineCount == 2)
        #expect(index.lineNumber(atUTF16Offset: 3) == 2)
    }

    @Test func incrementalDeleteRemovesLine() {
        var index = LineStartIndex()
        index.rebuild(from: "a\nb")
        index.applyEdit(
            editedRange: NSRange(location: 1, length: 1),
            changeInLength: -1,
            insertedText: "",
            fullText: "ab"
        )
        #expect(index.lineCount == 1)
        #expect(index.lineNumber(atUTF16Offset: 1) == 1)
    }
}
