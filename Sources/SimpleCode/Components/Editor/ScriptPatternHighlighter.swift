import Foundation

/// Regex-based highlighter for JavaScript, TypeScript, and Python when tree-sitter SPM
/// packages omit external scanner object files (documented integration limitation).
actor ScriptPatternHighlighter: SyntaxHighlighter {
    private let languageID: LanguageID

    init(languageID: LanguageID) {
        self.languageID = languageID
    }

    func load(text: String, revision: Int) async -> HighlightBatch {
        let tokens = Self.highlight(text, languageID: languageID)
        let whole = NSRange(location: 0, length: text.utf16.count)
        return HighlightBatch(revision: revision, coveredRanges: [whole], tokens: tokens)
    }

    func applyEdit(
        fullText: String,
        edit: TextEditDescriptor,
        revision: Int,
        priorityUTF16Range: NSRange
    ) async -> (priority: HighlightBatch, remainder: HighlightBatch?) {
        let batch = await load(text: fullText, revision: revision)
        return (batch, nil)
    }

    func scheduleViewport(
        fullText: String,
        revision: Int,
        visibleUTF16Range: NSRange
    ) async -> (priority: HighlightBatch, remainder: HighlightBatch?) {
        let batch = await load(text: fullText, revision: revision)
        return (batch, nil)
    }

    private static func highlight(_ text: String, languageID: LanguageID) -> [SyntaxToken] {
        let ns = text as NSString
        var tokens: [SyntaxToken] = []
        let lineComment = languageID == .python || languageID == .shell ? "#" : "//"

        var lineStart = 0
        while lineStart < ns.length {
            var lineEnd = lineStart
            while lineEnd < ns.length {
                let ch = ns.character(at: lineEnd)
                if ch == 10 || ch == 13 { break }
                lineEnd += 1
            }
            let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
            let line = ns.substring(with: lineRange)

            if let commentRange = line.range(of: lineComment) {
                let offset = line.distance(from: line.startIndex, to: commentRange.lowerBound)
                tokens.append(SyntaxToken(
                    range: NSRange(location: lineRange.location + offset, length: line.count - offset),
                    category: .comment
                ))
            }

            applyRegex(#""([^"\\]|\\.)*""#, in: line, base: lineRange.location, category: .string, tokens: &tokens)
            applyRegex(#"'([^'\\]|\\.)*'"#, in: line, base: lineRange.location, category: .string, tokens: &tokens)
            applyRegex(#"\b\d+(\.\d+)?\b"#, in: line, base: lineRange.location, category: .number, tokens: &tokens)

            let keywords: [String]
            switch languageID {
            case .python:
                keywords = ["def", "class", "if", "elif", "else", "for", "while", "return", "import", "from", "as", "with", "try", "except", "pass", "break", "continue", "raise", "lambda", "yield", "True", "False", "None", "and", "or", "not", "in", "is"]
            case .javascript, .typescript, .tsx:
                keywords = ["function", "const", "let", "var", "if", "else", "for", "while", "return", "import", "export", "from", "class", "extends", "new", "try", "catch", "finally", "throw", "async", "await", "typeof", "instanceof", "switch", "case", "break", "continue", "default", "true", "false", "null", "undefined", "interface", "type", "enum", "implements", "public", "private", "protected", "readonly"]
            default:
                keywords = []
            }
            for word in keywords {
                let escaped = NSRegularExpression.escapedPattern(for: word)
                applyRegex(#"\b\#(escaped)\b"#, in: line, base: lineRange.location, category: .keyword, tokens: &tokens)
            }

            lineStart = lineEnd
            if lineStart < ns.length, ns.character(at: lineStart) == 13, lineStart + 1 < ns.length, ns.character(at: lineStart + 1) == 10 {
                lineStart += 2
            } else if lineStart < ns.length {
                lineStart += 1
            }
        }
        return tokens
    }

    private static func applyRegex(_ pattern: String, in line: String, base: Int, category: SyntaxCategory, tokens: inout [SyntaxToken]) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(location: 0, length: (line as NSString).length)
        for match in regex.matches(in: line, range: range) {
            tokens.append(SyntaxToken(range: NSRange(location: base + match.range.location, length: match.range.length), category: category))
        }
    }
}
