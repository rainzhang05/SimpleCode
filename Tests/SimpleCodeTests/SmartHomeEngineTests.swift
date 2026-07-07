import Foundation
import Testing
@testable import SimpleCode

struct SmartHomeEngineTests {
    @Test func firstPressGoesToFirstNonWhitespace() {
        let text = "    hello"
        let sel = NSRange(location: 9, length: 0)
        let result = SmartHomeEngine.home(text: text, selection: sel, isSecondPress: false)
        #expect(result.resultingSelections == [NSRange(location: 4, length: 0)])
    }

    @Test func secondPressGoesToColumnZero() {
        let text = "    hello"
        let sel = NSRange(location: 4, length: 0)
        let result = SmartHomeEngine.home(text: text, selection: sel, isSecondPress: true)
        #expect(result.resultingSelections == [NSRange(location: 0, length: 0)])
    }

    @Test func fromColumnZeroGoesToLineStart() {
        let text = "    hello"
        let sel = NSRange(location: 0, length: 0)
        let result = SmartHomeEngine.home(text: text, selection: sel, isSecondPress: false)
        #expect(result.resultingSelections == [NSRange(location: 0, length: 0)])
    }

    @Test func fromMiddleWhitespaceGoesToFirstNonWS() {
        let text = "    hello"
        let sel = NSRange(location: 2, length: 0)
        let result = SmartHomeEngine.home(text: text, selection: sel, isSecondPress: false)
        #expect(result.resultingSelections == [NSRange(location: 4, length: 0)])
    }

    @Test func pastFirstNonWhitespaceGoesToLineStart() {
        let text = "    hello"
        let sel = NSRange(location: 6, length: 0)
        let result = SmartHomeEngine.home(text: text, selection: sel, isSecondPress: false)
        #expect(result.resultingSelections == [NSRange(location: 4, length: 0)])
    }

    @Test func shiftHomeExtendsSelectionToSmartHomeTarget() {
        let text = "    hello"
        let sel = NSRange(location: 9, length: 0)
        let result = SmartHomeEngine.home(text: text, selection: sel, isSecondPress: false, extendSelection: true)
        #expect(result.resultingSelections == [NSRange(location: 4, length: 5)])
    }
}
