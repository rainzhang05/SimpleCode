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

    private enum InitialLexicalMode: Equatable {
        case normal
        case lineComment
        case blockComment
        case string(delimiter: UInt16, triple: Bool, allowsNewline: Bool)
    }

    private struct InitialLexicalState: Equatable {
        var mode: InitialLexicalMode = .normal
        var escaped = false
    }

    private struct InitialLexicalCheckpoint {
        let location: Int
        let state: InitialLexicalState
    }

    private let configuration: Configuration
    private var cachedText = ""
    private var cachedRevision = -1
    private var cachedTokens: [SyntaxToken] = []
    private var hasMultilineConstructs = false
    private var initialGeneration: UInt64 = 0
    private var initialRevision: Int?
    private var initialLexicalCheckpoint = InitialLexicalCheckpoint(
        location: 0,
        state: InitialLexicalState()
    )
    private var initialSawMultilineConstructs = false

    init(languageID: LanguageID) {
        configuration = Configuration(languageID: languageID)
    }

    func load(text: String, revision: Int) async -> HighlightBatch {
        invalidateInitialContinuation()
        let tokens = highlightEntireDocument(text)
        cachedText = text
        cachedRevision = revision
        cachedTokens = tokens
        hasMultilineConstructs = Self.containsMultilineConstructs(text, supportsBackticks: configuration.supportsBackticks)
        let wholeDocument = NSRange(location: 0, length: text.utf16.count)
        return HighlightBatch(revision: revision, coveredRanges: [wholeDocument], tokens: tokens)
    }

    func prepareInitial(
        text: String,
        revision: Int,
        priorityUTF16Range: NSRange
    ) async -> InitialHighlightPage {
        initialGeneration &+= 1
        initialRevision = revision
        initialLexicalCheckpoint = InitialLexicalCheckpoint(
            location: 0,
            state: InitialLexicalState()
        )
        initialSawMultilineConstructs = false
        let priority = NSIntersectionRange(
            priorityUTF16Range,
            NSRange(location: 0, length: text.utf16.count)
        )
        let remaining = InitialHighlightPaging.remainingRanges(
            documentLength: text.utf16.count,
            excluding: priority
        )
        let initialCursor = remaining.isEmpty
            ? nil
            : InitialHighlightCursor(
                generation: initialGeneration,
                revision: revision,
                remainingRanges: remaining
            )
        let tokens = highlightInitialPage(
            text,
            restrictedTo: priority
        )
        _ = initialCheckpoint(at: NSMaxRange(priority), in: text)
        cachedText = text
        cachedRevision = revision
        cachedTokens = tokens
        hasMultilineConstructs = initialCursor != nil || initialSawMultilineConstructs
        if initialCursor == nil {
            initialRevision = nil
            initialLexicalCheckpoint = InitialLexicalCheckpoint(
                location: 0,
                state: InitialLexicalState()
            )
        }
        return InitialHighlightPage(
            batch: HighlightBatch(revision: revision, coveredRanges: [priority], tokens: tokens),
            next: initialCursor
        )
    }

    func continueInitial(
        _ cursor: InitialHighlightCursor,
        pageSizeUTF16: Int
    ) async -> InitialHighlightPage? {
        guard cursor.generation == initialGeneration,
              cursor.revision == initialRevision,
              cachedRevision == cursor.revision,
              let pageRange = InitialHighlightPaging.nextPageRange(
                in: cachedText,
                cursor: cursor,
                pageSizeUTF16: pageSizeUTF16
              ) else { return nil }
        let pageTokens = highlightInitialPage(
            cachedText,
            restrictedTo: pageRange
        )
        _ = initialCheckpoint(at: NSMaxRange(pageRange), in: cachedText)
        cachedTokens.append(contentsOf: pageTokens)
        let next = InitialHighlightPaging.advancing(cursor, past: pageRange)
        if next == nil {
            initialRevision = nil
            hasMultilineConstructs = initialSawMultilineConstructs
            initialLexicalCheckpoint = InitialLexicalCheckpoint(
                location: 0,
                state: InitialLexicalState()
            )
        }
        return InitialHighlightPage(
            batch: HighlightBatch(
                revision: cursor.revision,
                coveredRanges: [pageRange],
                tokens: pageTokens
            ),
            next: next
        )
    }

    func applyEdit(
        fullText: String,
        edit: TextEditDescriptor,
        revision: Int,
        priorityUTF16Range: NSRange
    ) async -> (priority: HighlightBatch, remainder: HighlightBatch?) {
        let wasPreparingInitialPages = initialRevision != nil
        invalidateInitialContinuation()
        guard !wasPreparingInitialPages,
              cachedRevision == revision - 1,
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
        if initialRevision == revision {
            var visibleTokens: [SyntaxToken] = []
            for range in visibleRanges {
                visibleTokens.append(contentsOf: highlightInitialPage(
                    fullText,
                    restrictedTo: range
                ))
            }
            return (
                HighlightBatch(
                    revision: revision,
                    coveredRanges: visibleRanges,
                    tokens: visibleTokens
                ),
                nil
            )
        }
        return (
            HighlightBatch(
                revision: revision,
                coveredRanges: visibleRanges,
                tokens: tokens(in: visibleRanges, from: cachedTokens)
            ),
            nil
        )
    }

    private func invalidateInitialContinuation() {
        initialGeneration &+= 1
        initialRevision = nil
        initialLexicalCheckpoint = InitialLexicalCheckpoint(
            location: 0,
            state: InitialLexicalState()
        )
        initialSawMultilineConstructs = false
    }

    private func initialCheckpoint(at offset: Int, in text: String) -> InitialLexicalCheckpoint {
        let string = text as NSString
        let target = max(0, min(offset, string.length))
        let startingCheckpoint = initialLexicalCheckpoint.location <= target
            ? initialLexicalCheckpoint
            : InitialLexicalCheckpoint(location: 0, state: InitialLexicalState())
        guard startingCheckpoint.location < target else { return startingCheckpoint }
        var state = startingCheckpoint.state
        var sawMultilineConstruct = false
        let reachedLocation = advanceInitialLexicalState(
            in: string,
            from: startingCheckpoint.location,
            to: target,
            state: &state,
            hasMultilineConstructs: &sawMultilineConstruct
        )
        initialSawMultilineConstructs = initialSawMultilineConstructs || sawMultilineConstruct
        let checkpoint = InitialLexicalCheckpoint(location: reachedLocation, state: state)
        initialLexicalCheckpoint = checkpoint
        return checkpoint
    }

    @discardableResult
    private func advanceInitialLexicalState(
        in text: NSString,
        from start: Int,
        to end: Int,
        state: inout InitialLexicalState,
        hasMultilineConstructs: inout Bool
    ) -> Int {
        var location = max(0, start)
        let limit = max(location, min(end, text.length))
        while location < limit {
            let unit = text.character(at: location)
            switch state.mode {
            case .normal:
                if configuration.supportsSlashComments,
                   unit == 47,
                   location + 1 < text.length {
                    guard location + 1 < limit else { return location }
                    let next = text.character(at: location + 1)
                    if next == 47 {
                        state.mode = .lineComment
                        location += 2
                        continue
                    }
                    if next == 42 {
                        state.mode = .blockComment
                        state.escaped = false
                        hasMultilineConstructs = true
                        location += 2
                        continue
                    }
                }
                if !configuration.supportsSlashComments, unit == configuration.lineComment {
                    state.mode = .lineComment
                    location += 1
                    continue
                }
                if (unit == 34 || unit == 39),
                   location + 2 < text.length,
                   text.character(at: location + 1) == unit,
                   text.character(at: location + 2) == unit {
                    guard location + 2 < limit else { return location }
                    state.mode = .string(delimiter: unit, triple: true, allowsNewline: true)
                    state.escaped = false
                    hasMultilineConstructs = true
                    location += 3
                    continue
                }
                if unit == 34 || unit == 39 || (configuration.supportsBackticks && unit == 96) {
                    let allowsNewline = unit == 96
                    state.mode = .string(delimiter: unit, triple: false, allowsNewline: allowsNewline)
                    state.escaped = false
                    if allowsNewline { hasMultilineConstructs = true }
                    location += 1
                    continue
                }
                location += 1

            case .lineComment:
                if unit == 10 || unit == 13 {
                    state.mode = .normal
                }
                location += 1

            case .blockComment:
                if unit == 42,
                   location + 1 < text.length,
                   text.character(at: location + 1) == 47 {
                    guard location + 1 < limit else { return location }
                    state.mode = .normal
                    location += 2
                } else {
                    location += 1
                }

            case let .string(delimiter, triple, allowsNewline):
                if state.escaped {
                    state.escaped = false
                    location += 1
                    continue
                }
                if unit == 92 {
                    state.escaped = true
                    location += 1
                    continue
                }
                if triple,
                   unit == delimiter,
                   location + 2 < text.length,
                   text.character(at: location + 1) == delimiter,
                   text.character(at: location + 2) == delimiter {
                    guard location + 2 < limit else { return location }
                    state.mode = .normal
                    location += 3
                    continue
                }
                if !triple, unit == delimiter {
                    state.mode = .normal
                    location += 1
                    continue
                }
                if !allowsNewline, (unit == 10 || unit == 13) {
                    state.mode = .normal
                }
                location += 1
            }
        }
        return location
    }

    private func highlightInitialPage(
        _ text: String,
        restrictedTo range: NSRange
    ) -> [SyntaxToken] {
        let string = text as NSString
        let covered = NSIntersectionRange(range, NSRange(location: 0, length: string.length))
        guard covered.length > 0 else { return [] }
        let end = NSMaxRange(covered)
        // A checkpoint stops before a multi-unit delimiter that crosses its
        // requested offset. Re-lexing those one or two preceding units and then
        // clipping emitted tokens keeps both pages correct without partial state.
        let checkpoint = initialCheckpoint(at: covered.location, in: text)
        var location = checkpoint.location
        var state = checkpoint.state
        var tokens: [SyntaxToken] = []

        while location < end {
            let unit = string.character(at: location)
            switch state.mode {
            case .lineComment:
                let start = location
                while location < end {
                    let current = string.character(at: location)
                    if current == 10 || current == 13 {
                        state.mode = .normal
                        break
                    }
                    location += 1
                }
                if location > start {
                    tokens.append(SyntaxToken(
                        range: NSRange(location: start, length: location - start),
                        category: .comment
                    ))
                }

            case .blockComment:
                let start = location
                while location < end {
                    if string.character(at: location) == 42,
                       location + 1 < end,
                       string.character(at: location + 1) == 47 {
                        location += 2
                        state.mode = .normal
                        break
                    }
                    location += 1
                }
                tokens.append(SyntaxToken(
                    range: NSRange(location: start, length: location - start),
                    category: .comment
                ))

            case let .string(delimiter, triple, allowsNewline):
                let start = location
                while location < end {
                    let current = string.character(at: location)
                    if state.escaped {
                        state.escaped = false
                        location += 1
                        continue
                    }
                    if current == 92 {
                        state.escaped = true
                        location += 1
                        continue
                    }
                    if triple,
                       current == delimiter,
                       location + 2 < end,
                       string.character(at: location + 1) == delimiter,
                       string.character(at: location + 2) == delimiter {
                        location += 3
                        state.mode = .normal
                        break
                    }
                    location += 1
                    if !triple, current == delimiter {
                        state.mode = .normal
                        break
                    }
                    if !allowsNewline, (current == 10 || current == 13) {
                        state.mode = .normal
                        break
                    }
                }
                tokens.append(SyntaxToken(
                    range: NSRange(location: start, length: location - start),
                    category: .string
                ))

            case .normal:
                if isWhitespace(unit) || unit == 10 || unit == 13 {
                    location += 1
                    continue
                }
                if configuration.supportsSlashComments,
                   unit == 47,
                   location + 1 < string.length {
                    let next = string.character(at: location + 1)
                    if next == 47 {
                        tokens.append(SyntaxToken(
                            range: NSRange(location: location, length: min(2, end - location)),
                            category: .comment
                        ))
                        location = min(end, location + 2)
                        state.mode = .lineComment
                        continue
                    }
                    if next == 42 {
                        tokens.append(SyntaxToken(
                            range: NSRange(location: location, length: min(2, end - location)),
                            category: .comment
                        ))
                        location = min(end, location + 2)
                        state.mode = .blockComment
                        continue
                    }
                }
                if !configuration.supportsSlashComments, unit == configuration.lineComment {
                    tokens.append(SyntaxToken(
                        range: NSRange(location: location, length: 1),
                        category: .comment
                    ))
                    location += 1
                    state.mode = .lineComment
                    continue
                }
                if (unit == 34 || unit == 39),
                   location + 2 < string.length,
                   string.character(at: location + 1) == unit,
                   string.character(at: location + 2) == unit {
                    tokens.append(SyntaxToken(
                        range: NSRange(location: location, length: min(3, end - location)),
                        category: .string
                    ))
                    location = min(end, location + 3)
                    state.mode = .string(delimiter: unit, triple: true, allowsNewline: true)
                    continue
                }
                if unit == 34 || unit == 39 || (configuration.supportsBackticks && unit == 96) {
                    tokens.append(SyntaxToken(
                        range: NSRange(location: location, length: 1),
                        category: .string
                    ))
                    location += 1
                    state.mode = .string(
                        delimiter: unit,
                        triple: false,
                        allowsNewline: unit == 96
                    )
                    continue
                }

                if isDigit(unit) {
                    let numberEnd = endOfNumber(in: string, startingAt: location, limit: end)
                    tokens.append(SyntaxToken(
                        range: NSRange(location: location, length: numberEnd - location),
                        category: .number
                    ))
                    location = numberEnd
                    continue
                }
                if isIdentifierStart(unit) {
                    let identifierEnd = endOfIdentifier(in: string, startingAt: location, limit: end)
                    let identifier = string.substring(with: NSRange(
                        location: location,
                        length: identifierEnd - location
                    ))
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
        }
        return tokens.compactMap { token in
            let clippedRange = NSIntersectionRange(token.range, covered)
            guard clippedRange.length > 0 else { return nil }
            return SyntaxToken(range: clippedRange, category: token.category)
        }
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
        var cachedLineEnd = location

        while location < end {
            let unit = nsText.character(at: location)

            if isWhitespace(unit) || unit == 10 || unit == 13 {
                location += 1
                continue
            }

            if location >= cachedLineEnd {
                cachedLineEnd = min(end, Self.lineEnd(after: location, in: nsText))
            }
            let lineEnd = cachedLineEnd
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
                    let searchStart = location + 2
                    let closing = searchStart < end
                        ? nsText.range(
                            of: "*/",
                            options: [],
                            range: NSRange(location: searchStart, length: end - searchStart)
                        )
                        : NSRange(location: NSNotFound, length: 0)
                    let commentEnd = closing.location == NSNotFound ? end : min(end, NSMaxRange(closing))
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
                let searchStart = location + 3
                let closing = searchStart < end
                    ? nsText.range(
                        of: delimiter,
                        options: [],
                        range: NSRange(location: searchStart, length: end - searchStart)
                    )
                    : NSRange(location: NSNotFound, length: 0)
                let stringEnd = closing.location == NSNotFound ? end : min(end, NSMaxRange(closing))
                tokens.append(SyntaxToken(range: NSRange(location: location, length: stringEnd - location), category: .string))
                location = stringEnd
                continue
            }
            if unit == 34 || unit == 39 || (configuration.supportsBackticks && unit == 96) {
                let limit = unit == 96 ? end : lineEnd
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
