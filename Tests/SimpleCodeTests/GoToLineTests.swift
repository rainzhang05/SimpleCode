import Foundation
import Testing
@testable import SimpleCode

@MainActor
struct GoToLineTests {
    @Test func resolvesValidLineOffset() {
        let controller = GoToLineController()
        var index = LineStartIndex()
        index.rebuild(from: "a\nbb\nc")
        controller.lineInput = "2"
        let offset = controller.resolve(lineStartIndex: index, lineCount: index.lineCount, text: "a\nbb\nc")
        #expect(offset == 2)
    }

    @Test func rejectsOutOfRangeLine() {
        let controller = GoToLineController()
        var index = LineStartIndex()
        index.rebuild(from: "a\nb")
        controller.lineInput = "9"
        let offset = controller.resolve(lineStartIndex: index, lineCount: index.lineCount, text: "a\nb")
        #expect(offset == nil)
        #expect(controller.errorMessage != nil)
    }

    @Test func acceptsLastLine() {
        let controller = GoToLineController()
        var index = LineStartIndex()
        index.rebuild(from: "one\ntwo\nthree")
        controller.lineInput = "3"
        let offset = controller.resolve(lineStartIndex: index, lineCount: index.lineCount, text: "one\ntwo\nthree")
        #expect(offset == 8)
    }

    @Test func resolvesLineAndColumn() {
        let text = "a\nbb\nc"
        let controller = GoToLineController()
        var index = LineStartIndex()
        index.rebuild(from: text)
        controller.lineInput = "2:2"
        let offset = controller.resolve(lineStartIndex: index, lineCount: index.lineCount, text: text)
        #expect(offset == 3)
    }

    @Test func clampsColumnBeyondLineEnd() {
        let text = "a\r\nbb\r\nc"
        let controller = GoToLineController()
        var index = LineStartIndex()
        index.rebuild(from: text)
        controller.lineInput = "2:99"
        let offset = controller.resolve(lineStartIndex: index, lineCount: index.lineCount, text: text)
        #expect(offset == 5)
    }

    @Test func rejectsInvalidLineOrColumnInput() {
        let text = "a\nb"
        var index = LineStartIndex()
        index.rebuild(from: text)
        for input in ["", "0", "-1", "abc", "1:0", "1:-2", "1:abc"] {
            let controller = GoToLineController()
            controller.lineInput = input
            #expect(controller.resolve(lineStartIndex: index, lineCount: index.lineCount, text: text) == nil)
            #expect(controller.errorMessage != nil)
        }
    }
}
