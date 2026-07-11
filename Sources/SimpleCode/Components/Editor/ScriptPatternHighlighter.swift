import Foundation

/// A lightweight lexical highlighter for the JavaScript/TypeScript/Python family.
///
/// These grammars are deliberately kept inside the existing twelve-language scope.
/// The lexer is line-oriented, so normal single-line edits update only the changed
/// line (and one neighbour for newline edits) rather than recompiling regular
/// expressions and reparsing the full document on every keystroke.
actor ScriptPatternHighlighter: SyntaxHighlighter {
    private struct Configuration {
        let lineComment: UInt16
        let supportsSlashComments: Bool
        let supportsBackticks: Bool
        let keywords: Set<String>
        let constants: Set<String>

        init(languageID: LanguageID) {
            switch languageID {
            case .python:
                lineComment = 35 // #
                supportsSlashComments = false
                supportsBackticks = false
                keywords = [
                    "def", "class", "if", "elif", "else", "for", "while", "return", "import", "from", "as", "with", "try", "except", "finally", "pass", "break", "continue", "raise", "lambda", "yield", "async", "await", "match", "case", "global", "nonlocal", "del", "assert", "in", "is", "and", "or", "not"
                ]
                constants = ["True", "False", "None"]
            case .javascript, .typescript, .tsx:
                lineComment = 47 // /
                supportsSlashComments = true
                supportsBackticks = true
                keywords = [
                    "function", "const", "let", "var", "if", "else", "for", "while", "return", "import", "export", "from", "class", "extends", "new", "try", "catch", "finally", "throw", "async", "await", "typeof", "instanceof", "switch", "case", "break", "continue", "default", "interface", "type", "enum", "implements", "public", "private", "protected", "readonly", "declare", "namespace", "keyof", "infer", "satisfies", "void", "delete", "in", "of", "get", "set", "static", "abstract"
                ]
                constants = ["true", "false", "null", "undefined", "NaN", "Infinity"]
            default:
                lineComment = 47
                supportsSlashComments = true
                supportsBackticks = false
                keywords = []
                constants = []
            }
        }
    }

    private let configuration: Configuration
    private var cachedText = ""
    private var cachedRevision = -1
    private var cachedTokens: [SyntaxToken] = []
    private var hasMultilineConstructs = false

    init(languageID: LanguageID) {
        configuration = Configuration(languageID: languageID)
    }

    func load(text: String, revision: Int) async -> HighlightBatch {
        let tokens = highlightEntireDocument(text)
        cachedText = text
        cachedRevision = revision
        cachedTokens = tokens
        hasMultilineConstructs = Self.containsMultilineConstructs(text, supportsBackticks: configuration.supportsBackticks)
        let wholeDocument = NSRange(location: 0, length: text.utf16.count)
        return HighlightBatch(revision: revision, coveredRanges: [wholeDocument], tokens: tokens)
    }

    func applyEdit(
        fullText: String,
        edit: TextEditDescriptor,
        revision: Int,
        priorityUTF16Range: NSRange
    ) async -> (priority: HighlightBatch, remainder: HighlightBatch?) {
        guard cachedRevision == revision - 1,
              !hasMultilineConstructs,
              !Self.editTouchesMultilineSyntax(
                oldText: cachedText,
                newText: fullText,
                edit: edit,
                supportsBackticks: configuration.supportsBackticks
              ) else {
            let batch = await load(text: fullText, revision: revision)
            return (batch, nil)
        }

        let oldAffectedRange = Self.expandedLineRange(
            around: NSRange(
                location: edit.startUTF16,
                length: max(0, edit.oldEndUTF16 - edit.startUTF16)
            ),
            in: cachedText
        )
        let newAffectedRange = Self.expandedLineRange(
            around: NSRange(
                location: edit.startUTF16,
                length: max(0, edit.newEndUTF16 - edit.startUTF16)
            ),
            in: fullText
        )
        let offsetDelta = fullText.utf16.count - cachedText.utf16.count
        let replacementTokens = highlight(fullText, restrictedTo: newAffectedRange)

        var updated: [SyntaxToken] = []
        updated.reserveCapacity(cachedTokens.count + replacementTokens.count)
        for token in cachedTokens {
            if NSIntersectionRange(token.range, oldAffectedRange).length > 0 {
                continue
            }
            if token.range.location >= NSMaxRange(oldAffectedRange) {
                updated.append(SyntaxToken(
                    range: NSRange(location: token.range.location + offsetDelta, length: token.range.length),
                    category: token.category
                ))
            } else {
                updated.append(token)
            }
        }
        updated.append(contentsOf: replacementTokens)
        updated.sort { lhs, rhs in
            lhs.range.location == rhs.range.location
                ? lhs.range.length < rhs.range.length
                : lhs.range.location < rhs.range.location
        }

        cachedText = fullText
        cachedRevision = revision
        cachedTokens = updated

        let coveredRanges = Self.mergedRanges([priorityUTF16Range, newAffectedRange], documentLength: fullText.utf16.count)
        let tokens = tokens(in: coveredRanges, from: updated)
        return (
            HighlightBatch(revision: revision, coveredRanges: coveredRanges, tokens: tokens),
            nil
        )
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
