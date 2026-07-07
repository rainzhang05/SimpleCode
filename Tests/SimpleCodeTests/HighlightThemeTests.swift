import Testing
@testable import SimpleCode

struct HighlightThemeTests {
    @Test func exactMatchesAreMappedDirectly() {
        #expect(HighlightTheme.category(forCapture: "comment.documentation") == .documentationComment)
        #expect(HighlightTheme.category(forCapture: "constructor") == .function)
        #expect(HighlightTheme.category(forCapture: "boolean") == .constant)
        #expect(HighlightTheme.category(forCapture: "number.float") == .number)
    }

    @Test func dottedCapturesFallBackToTheirFirstComponent() {
        #expect(HighlightTheme.category(forCapture: "keyword.function") == .keyword)
        #expect(HighlightTheme.category(forCapture: "keyword.conditional.ternary") == .keyword)
        #expect(HighlightTheme.category(forCapture: "variable.parameter") == .variable)
        #expect(HighlightTheme.category(forCapture: "function.call") == .function)
        #expect(HighlightTheme.category(forCapture: "punctuation.delimiter") == .punctuation)
    }

    @Test func topLevelCapturesMapDirectly() {
        #expect(HighlightTheme.category(forCapture: "string") == .string)
        #expect(HighlightTheme.category(forCapture: "comment") == .comment)
        #expect(HighlightTheme.category(forCapture: "type") == .type)
        #expect(HighlightTheme.category(forCapture: "operator") == .operator)
    }

    @Test func unrecognizedCapturesAreSkippedRatherThanStyledAsPlain() {
        // "spell" is emitted alongside "comment" by the grammar's query for
        // spell-checking hints, not coloring; it must not overwrite a color
        // already applied by another capture on the same range.
        #expect(HighlightTheme.category(forCapture: "spell") == nil)
        #expect(HighlightTheme.category(forCapture: "totally.unknown.capture") == nil)
    }

    @Test func lightAndDarkPalettesDefineTheSameCategories() {
        for category in SyntaxCategory.allCases where category != .plain {
            let light = HighlightTheme.color(for: category, appearance: .light)
            let dark = HighlightTheme.color(for: category, appearance: .dark)
            // Colors must differ meaningfully between appearances for legibility;
            // this is a smoke check, not a full contrast audit.
            #expect(light != dark)
        }
    }
}
