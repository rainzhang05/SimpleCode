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
        guard cachedRevision == revision else {
            let batch = await load(text: fullText, revision: revision)
            let visibleRanges = Self.mergedRanges([visibleUTF16Range], documentLength: fullText.utf16.count)
            return (
                HighlightBatch(
                    revision: revision,
                    coveredRanges: visibleRanges,
                    tokens: tokens(in: visibleRanges, from: batch.tokens)
                ),
                nil
            )
        }

        let visibleRanges = Self.mergedRanges([visibleUTF16Range], documentLength: fullText.utf16.count)
        return (
            HighlightBatch(
                revision: revision,
                coveredRanges: visibleRanges,
                tokens: tokens(in: visibleRanges, from: cachedTokens)
            ),
            nil
        )
    }

    private func highlightEntireDocument(_ text: String) -> [SyntaxToken] {
        highlight(text, restrictedTo: NSRange(location: 0, length: text.utf16.count))
    }

    private func highlight(_ text: String, restrictedTo range: NSRange) -> [SyntaxToken] {
        let nsText = text as NSString
        guard nsText.length > 0, range.length > 0 else { return [] }
        var tokens: [SyntaxToken] = []
        var location = max(0, min(range.location, nsText.length))
        let end = min(nsText.length, NSMaxRange(range))

        while location < end {
            let unit = nsText.character(at: location)

            if isWhitespace(unit) || unit == 10 || unit == 13 {
                location += 1
                continue
            }

            let lineEnd = Self.lineEnd(after: location, in: nsText)
            if configuration.supportsSlashComments,
               unit == 47,
               location + 1 < nsText.length {
                let next = nsText.character(at: location + 1)
                if next == 47 {
                    tokens.append(SyntaxToken(range: NSRange(location: location, length: lineEnd - location), category: .comment))
                    location = lineEnd
                    continue
                }
                if next == 42 {
                    let closing = nsText.range(
                        of: "*/",
                        options: [],
                        range: NSRange(location: location + 2, length: nsText.length - location - 2)
                    )
                    let commentEnd = closing.location == NSNotFound ? nsText.length : NSMaxRange(closing)
                    tokens.append(SyntaxToken(range: NSRange(location: location, length: commentEnd - location), category: .comment))
                    location = commentEnd
                    continue
                }
            }
            if !configuration.supportsSlashComments, unit == configuration.lineComment {
                tokens.append(SyntaxToken(range: NSRange(location: location, length: lineEnd - location), category: .comment))
                location = lineEnd
                continue
            }

            if (unit == 34 || unit == 39),
               location + 2 < nsText.length,
               nsText.character(at: location + 1) == unit,
               nsText.character(at: location + 2) == unit {
                let delimiter = String(UnicodeScalar(unit)!) + String(UnicodeScalar(unit)!) + String(UnicodeScalar(unit)!)
                let closing = nsText.range(
                    of: delimiter,
                    options: [],
                    range: NSRange(location: location + 3, length: nsText.length - location - 3)
                )
                let stringEnd = closing.location == NSNotFound ? nsText.length : NSMaxRange(closing)
                tokens.append(SyntaxToken(range: NSRange(location: location, length: stringEnd - location), category: .string))
                location = stringEnd
                continue
            }
            if unit == 34 || unit == 39 || (configuration.supportsBackticks && unit == 96) {
                let limit = unit == 96 ? nsText.length : lineEnd
                let stringEnd = endOfString(in: nsText, startingAt: location, limit: limit, delimiter: unit)
                tokens.append(SyntaxToken(
                    range: NSRange(location: location, length: max(1, stringEnd - location)),
                    category: .string
                ))
                location = stringEnd
                continue
            }

            if isDigit(unit) {
                let numberEnd = endOfNumber(in: nsText, startingAt: location, limit: lineEnd)
                tokens.append(SyntaxToken(
                    range: NSRange(location: location, length: numberEnd - location),
                    category: .number
                ))
                location = numberEnd
                continue
            }

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
