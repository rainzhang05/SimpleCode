import Foundation

/// Applies save-time text transformations configured in global editor settings.
enum SaveTransformService {
    static func transform(
        text: String,
        language: LanguageID,
        lineEnding: LineEndingMode,
        trimTrailingWhitespace: Bool,
        ensureFinalNewline: Bool
    ) -> String {
        var result = text
        if trimTrailingWhitespace {
            result = trimTrailingWhitespacePreservingMarkdownHardBreaks(result, language: language)
        }
        if ensureFinalNewline, !result.isEmpty, !result.hasSuffix(lineEnding.newlineString) {
            result += lineEnding.newlineString
        }
        return result
    }

    private static func trimTrailingWhitespacePreservingMarkdownHardBreaks(_ text: String, language: LanguageID) -> String {
        var output = ""
        var line = ""
        let carriageReturn = UnicodeScalar("\r")
        let lineFeed = UnicodeScalar("\n")

        var index = text.unicodeScalars.startIndex
        while index < text.unicodeScalars.endIndex {
            let scalar = text.unicodeScalars[index]
            if scalar == carriageReturn {
                output += trimmedLine(line, language: language)
                line.removeAll(keepingCapacity: true)
                output.unicodeScalars.append(carriageReturn)
                let next = text.unicodeScalars.index(after: index)
                if next < text.unicodeScalars.endIndex, text.unicodeScalars[next] == lineFeed {
                    output.unicodeScalars.append(lineFeed)
                    index = text.unicodeScalars.index(after: next)
                } else {
                    index = next
                }
            } else if scalar == lineFeed {
                output += trimmedLine(line, language: language)
                line.removeAll(keepingCapacity: true)
                output.unicodeScalars.append(lineFeed)
                index = text.unicodeScalars.index(after: index)
            } else {
                line.unicodeScalars.append(scalar)
                index = text.unicodeScalars.index(after: index)
            }
        }
        output += trimmedLine(line, language: language)
        return output
    }

    private static func trimmedLine(_ line: String, language: LanguageID) -> String {
        if language == .markdown, line.hasSuffix("  ") {
            return line
        }
        return line.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression)
    }
}
