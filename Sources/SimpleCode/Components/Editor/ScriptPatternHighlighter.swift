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

            if isIdentifierStart(unit) {
                let identifierEnd = endOfIdentifier(in: nsText, startingAt: location, limit: lineEnd)
                let identifier = nsText.substring(with: NSRange(location: location, length: identifierEnd - location))
                if configuration.keywords.contains(identifier) {
                    tokens.append(SyntaxToken(
                        range: NSRange(location: location, length: identifierEnd - location),
                        category: .keyword
                    ))
                } else if configuration.constants.contains(identifier) {
                    tokens.append(SyntaxToken(
                        range: NSRange(location: location, length: identifierEnd - location),
                        category: .constant
                    ))
                }
                location = identifierEnd
                continue
            }

            location += 1
        }
        return tokens
    }

    private func endOfString(in text: NSString, startingAt start: Int, limit: Int, delimiter: UInt16) -> Int {
        var index = start + 1
        while index < limit {
            let unit = text.character(at: index)
            if unit == 92 { // escaped character
                index = min(limit, index + 2)
                continue
            }
            index += 1
            if unit == delimiter { break }
        }
        return index
    }

    private func endOfNumber(in text: NSString, startingAt start: Int, limit: Int) -> Int {
        var index = start
        while index < limit {
            let unit = text.character(at: index)
            guard isDigit(unit) || unit == 46 || unit == 95 || unit == 120 || unit == 88 || unit == 101 || unit == 69 || unit == 43 || unit == 45 || (unit >= 65 && unit <= 70) || (unit >= 97 && unit <= 102) else {
                break
            }
            index += 1
        }
        return index
    }

    private func endOfIdentifier(in text: NSString, startingAt start: Int, limit: Int) -> Int {
        var index = start + 1
        while index < limit, isIdentifierContinue(text.character(at: index)) {
            index += 1
        }
        return index
    }

    private func tokens(in ranges: [NSRange], from tokens: [SyntaxToken]) -> [SyntaxToken] {
        tokens.filter { token in
            ranges.contains { NSIntersectionRange(token.range, $0).length > 0 }
        }
    }

    private static func mergedRanges(_ ranges: [NSRange], documentLength: Int) -> [NSRange] {
        let clamped = ranges.compactMap { range -> NSRange? in
            let lower = max(0, min(range.location, documentLength))
            let upper = max(lower, min(NSMaxRange(range), documentLength))
            return upper > lower ? NSRange(location: lower, length: upper - lower) : nil
        }.sorted { $0.location < $1.location }

        var merged: [NSRange] = []
        for range in clamped {
            guard var previous = merged.last else {
                merged.append(range)
                continue
            }
            if range.location <= NSMaxRange(previous) {
                previous.length = max(NSMaxRange(previous), NSMaxRange(range)) - previous.location
                merged[merged.count - 1] = previous
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private static func expandedLineRange(around range: NSRange, in text: String) -> NSRange {
        let nsText = text as NSString
        guard nsText.length > 0 else { return NSRange(location: 0, length: 0) }
        let lower = max(0, min(range.location, nsText.length - 1))
        let upperProbe = max(lower, min(max(range.location, NSMaxRange(range) - 1), nsText.length - 1))
        let first = nsText.lineRange(for: NSRange(location: lower, length: 0))
        let last = nsText.lineRange(for: NSRange(location: upperProbe, length: 0))
        var end = NSMaxRange(last)
        if end < nsText.length {
            end = NSMaxRange(nsText.lineRange(for: NSRange(location: end, length: 0)))
        }
        return NSRange(location: first.location, length: end - first.location)
    }

    private static func lineEnd(after location: Int, in text: NSString) -> Int {
        var index = location
        while index < text.length {
            let unit = text.character(at: index)
            if unit == 10 || unit == 13 { break }
            index += 1
        }
        return index
    }

    private static func containsMultilineConstructs(_ text: String, supportsBackticks: Bool) -> Bool {
        containsMultilineBlockComment(in: text)
            || text.contains("\\\n")
            || text.contains("'''")
            || text.contains("\"\"\"")
            || (supportsBackticks && containsMultilineBacktickString(in: text))
    }

    private static func containsMultilineBacktickString(in text: String) -> Bool {
        let nsText = text as NSString
        var index = 0
        var isInsideTemplate = false

        while index < nsText.length {
            let unit = nsText.character(at: index)
            if unit == 92 { // escaped character
                index = min(nsText.length, index + 2)
                continue
            }
            if unit == 96 { // `
                isInsideTemplate.toggle()
            } else if isInsideTemplate, unit == 10 || unit == 13 {
                return true
            }
            index += 1
        }
        return false
    }

    private static func containsMultilineBlockComment(in text: String) -> Bool {
        let nsText = text as NSString
        var searchStart = 0
        while searchStart < nsText.length {
            let remaining = NSRange(location: searchStart, length: nsText.length - searchStart)
            let opening = nsText.range(of: "/*", options: [], range: remaining)
            guard opening.location != NSNotFound else { return false }
            let afterOpening = NSMaxRange(opening)
            let closing = nsText.range(
                of: "*/",
                options: [],
                range: NSRange(location: afterOpening, length: nsText.length - afterOpening)
            )
            guard closing.location != NSNotFound else { return true }
            let body = nsText.substring(with: NSRange(location: afterOpening, length: closing.location - afterOpening))
            if body.contains("\n") || body.contains("\r") { return true }
            searchStart = NSMaxRange(closing)
        }
        return false
    }

    private static func editTouchesMultilineSyntax(
        oldText: String,
        newText: String,
        edit: TextEditDescriptor,
        supportsBackticks: Bool
    ) -> Bool {
        let oldRange = NSRange(
            location: edit.startUTF16,
            length: max(0, edit.oldEndUTF16 - edit.startUTF16)
        )
        let newRange = NSRange(
            location: edit.startUTF16,
            length: max(0, edit.newEndUTF16 - edit.startUTF16)
        )
        let changedContext = neighborhood(around: oldRange, in: oldText)
            + neighborhood(around: newRange, in: newText)
        if containsMultilineConstructs(changedContext, supportsBackticks: supportsBackticks) {
            return true
        }

        // A line break or backtick edit can turn a previously one-line template
        // into a multiline string even when neither delimiter is within the tiny
        // edit neighborhood. Scan the complete document only for that uncommon
        // structural mutation; ordinary identifier edits stay line-local.
        guard supportsBackticks else { return false }
        let changedText = substring(oldRange, in: oldText) + substring(newRange, in: newText)
        guard changedText.contains("`") || changedText.contains("\n") || changedText.contains("\r") else {
            return false
        }
        return containsMultilineBacktickString(in: oldText)
            || containsMultilineBacktickString(in: newText)
    }

    private static func substring(_ range: NSRange, in text: String) -> String {
        let nsText = text as NSString
        let lower = max(0, min(range.location, nsText.length))
        let upper = max(lower, min(NSMaxRange(range), nsText.length))
        return nsText.substring(with: NSRange(location: lower, length: upper - lower))
    }

    private static func neighborhood(around range: NSRange, in text: String) -> String {
        let nsText = text as NSString
        guard nsText.length > 0 else { return "" }
        let lower = max(0, min(range.location - 3, nsText.length))
        let upper = min(nsText.length, max(NSMaxRange(range) + 3, lower))
        return nsText.substring(with: NSRange(location: lower, length: upper - lower))
    }

    private func isWhitespace(_ unit: UInt16) -> Bool {
        unit == 9 || unit == 32
    }

    private func isDigit(_ unit: UInt16) -> Bool {
        unit >= 48 && unit <= 57
    }

    private func isIdentifierStart(_ unit: UInt16) -> Bool {
        (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122) || unit == 95 || unit == 36
    }

    private func isIdentifierContinue(_ unit: UInt16) -> Bool {
        isIdentifierStart(unit) || isDigit(unit)
    }
}
