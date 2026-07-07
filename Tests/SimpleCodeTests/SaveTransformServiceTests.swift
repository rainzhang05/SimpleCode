import Testing
@testable import SimpleCode

struct SaveTransformServiceTests {
    @Test func trimTrailingWhitespacePreservesCRLFLineEndings() {
        let text = "one  \r\ntwo\t\r\nthree"
        let transformed = SaveTransformService.transform(
            text: text,
            language: .swift,
            lineEnding: .crlf,
            trimTrailingWhitespace: true,
            ensureFinalNewline: false
        )
        #expect(transformed == "one\r\ntwo\r\nthree")
    }

    @Test func trimTrailingWhitespacePreservesCRLineEndings() {
        let text = "one  \rtwo\t\r"
        let transformed = SaveTransformService.transform(
            text: text,
            language: .swift,
            lineEnding: .cr,
            trimTrailingWhitespace: true,
            ensureFinalNewline: false
        )
        #expect(transformed == "one\rtwo\r")
    }

    @Test func markdownHardBreakSpacesArePreserved() {
        let text = "line with hard break  \nplain trailing   \n"
        let transformed = SaveTransformService.transform(
            text: text,
            language: .markdown,
            lineEnding: .lf,
            trimTrailingWhitespace: true,
            ensureFinalNewline: false
        )
        #expect(transformed == "line with hard break  \nplain trailing   \n")
    }

    @Test func finalNewlineUsesConfiguredLineEnding() {
        let transformed = SaveTransformService.transform(
            text: "one",
            language: .swift,
            lineEnding: .crlf,
            trimTrailingWhitespace: false,
            ensureFinalNewline: true
        )
        #expect(transformed == "one\r\n")
    }
}
