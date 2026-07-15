import Foundation

/// Line-scoped syntax highlighting for the supported assembly files. Assembly is
/// naturally local to a source line, allowing edits to update a small token window
/// while preserving the already classified rest of a large file.
actor AssemblyPatternHighlighter: SyntaxHighlighter {
    private enum Patterns {
        static let label = regex(#"(?i)^\s*([A-Za-z_.@][\w.$@]*)\s*:"#)
        static let directive = regex(#"(?i)\.([A-Za-z_][\w.]*)"#)
        static let instruction = regex(#"(?i)\b(mov|movq|movl|movw|movb|lea|add|adc|sub|sbb|imul|mul|idiv|div|and|or|xor|not|neg|inc|dec|push|pop|call|ret|jmp|je|jne|jz|jnz|jg|jge|jl|jle|ja|jae|jb|jbe|cmp|test|nop|syscall|int|cli|sti|hlt|leave|enter|movz|movk|madd|msub|orr|eor|lsl|lsr|asr|b|bl|br|ldr|str|ldp|stp|adr|adrp|svc)\b"#)
        static let register = regex(#"(?i)\b(%?(?:r(?:ax|bx|cx|dx|si|di|bp|sp|8|9|10|11|12|13|14|15)(?:d|w|b)?|e(?:ax|bx|cx|dx|si|di|bp|sp)|a(?:x|h|l)|b(?:x|h|l)|c(?:x|h|l)|d(?:x|h|l)|si|di|bp|sp|r\d+b?)|x\d{1,2}|w\d{1,2}|sp|lr|pc|xzr|wzr)\b"#)
        static let number = regex(#"(?i)(?:\$|#)?0x[0-9a-f]+|(?:\$|#)?\b\d+\b"#)
        static let string = regex(#"\"([^\"\\]|\\.)*\""#)

        private static func regex(_ pattern: String) -> NSRegularExpression {
            // These constant patterns are validated at launch, not recompiled for
            // every source line or every keystroke.
            try! NSRegularExpression(pattern: pattern)
        }
    }

    private var cachedText = ""
    private var cachedRevision = -1
    private var cachedTokens: [SyntaxToken] = []
    private var initialGeneration: UInt64 = 0
    private var initialRevision: Int?

    func load(text: String, revision: Int) async -> HighlightBatch {
        invalidateInitialContinuation()
        let documentUTF16Count = (text as NSString).length
        let tokens = highlight(text, restrictedTo: NSRange(location: 0, length: documentUTF16Count))
        cachedText = text
        cachedRevision = revision
        cachedTokens = tokens
        return HighlightBatch(
            revision: revision,
            coveredRanges: [NSRange(location: 0, length: documentUTF16Count)],
            tokens: tokens
        )
    }

    func prepareInitial(
        text: String,
        revision: Int,
        priorityUTF16Range: NSRange
    ) async -> InitialHighlightPage {
        initialGeneration &+= 1
        initialRevision = revision
        let documentUTF16Count = (text as NSString).length
        let priority = NSIntersectionRange(
            priorityUTF16Range,
            NSRange(location: 0, length: documentUTF16Count)
        )
        let tokens = highlight(text, restrictedTo: priority)
        cachedText = text
        cachedRevision = revision
        cachedTokens = tokens
        let remaining = InitialHighlightPaging.remainingRanges(
            documentLength: documentUTF16Count,
            excluding: priority
        )
        if remaining.isEmpty {
            initialRevision = nil
        }
        return InitialHighlightPage(
            batch: HighlightBatch(revision: revision, coveredRanges: [priority], tokens: tokens),
            next: remaining.isEmpty
                ? nil
                : InitialHighlightCursor(
                    generation: initialGeneration,
                    revision: revision,
                    remainingRanges: remaining
                )
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
        let pageTokens = highlight(cachedText, restrictedTo: pageRange)
        cachedTokens.append(contentsOf: pageTokens)
        let next = InitialHighlightPaging.advancing(cursor, past: pageRange)
        if next == nil {
            initialRevision = nil
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
        guard !wasPreparingInitialPages, cachedRevision == revision - 1 else {
            let batch = await load(text: fullText, revision: revision)
            return (batch, nil)
        }

        let oldAffectedRange = Self.expandedLineRange(
            around: NSRange(location: edit.startUTF16, length: max(0, edit.oldEndUTF16 - edit.startUTF16)),
            in: cachedText
        )
        let newAffectedRange = Self.expandedLineRange(
            around: NSRange(location: edit.startUTF16, length: max(0, edit.newEndUTF16 - edit.startUTF16)),
            in: fullText
        )
        let offsetDelta = edit.newEndUTF16 - edit.oldEndUTF16
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
        return (
            HighlightBatch(
                revision: revision,
                coveredRanges: coveredRanges,
                tokens: tokens(in: coveredRanges, from: updated)
            ),
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
        if initialRevision == revision, let viewportRange = visibleRanges.first {
            let viewportTokens = highlight(fullText, restrictedTo: viewportRange)
            return (
                HighlightBatch(
                    revision: revision,
                    coveredRanges: visibleRanges,
                    tokens: viewportTokens
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
    }

    private func highlight(_ text: String, restrictedTo range: NSRange) -> [SyntaxToken] {
        let nsText = text as NSString
        guard nsText.length > 0, range.length > 0 else { return [] }
        var tokens: [SyntaxToken] = []
        var location = max(0, min(range.location, nsText.length))
        let end = min(nsText.length, NSMaxRange(range))

        while location < end {
            let fullLineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let lineRange = NSRange(
                location: location,
                length: min(end, NSMaxRange(fullLineRange)) - location
            )
            let contentRange = Self.contentRange(of: lineRange, in: nsText)
            tokens.append(contentsOf: highlightLine(nsText, range: contentRange))
            let next = NSMaxRange(lineRange)
            guard next > location else { break }
            location = next
        }
        return tokens
    }

    private func highlightLine(_ text: NSString, range: NSRange) -> [SyntaxToken] {
        guard range.length > 0 else { return [] }
        let comment = commentRange(in: text, range: range)
        let codeEnd = comment?.location ?? NSMaxRange(range)
        let codeRange = NSRange(location: range.location, length: max(0, codeEnd - range.location))
        let line = text.substring(with: codeRange)
        var tokens: [SyntaxToken] = []

        appendMatches(Patterns.label, in: line, base: codeRange.location, category: .label, to: &tokens)
        appendMatches(Patterns.directive, in: line, base: codeRange.location, category: .preprocessor, to: &tokens)
        appendMatches(Patterns.instruction, in: line, base: codeRange.location, category: .keyword, to: &tokens)
        appendMatches(Patterns.register, in: line, base: codeRange.location, category: .variable, to: &tokens)
        appendMatches(Patterns.number, in: line, base: codeRange.location, category: .number, to: &tokens)
        appendMatches(Patterns.string, in: line, base: codeRange.location, category: .string, to: &tokens)

        if let comment {
            tokens.append(SyntaxToken(range: comment, category: .comment))
        }
        return tokens
    }

    private func commentRange(in text: NSString, range: NSRange) -> NSRange? {
        let end = NSMaxRange(range)
        var index = range.location
        var delimiter: UInt16?

        while index < end {
            let unit = text.character(at: index)
            if let activeDelimiter = delimiter {
                if unit == 92 { // escaped string character
                    index = min(end, index + 2)
                    continue
                }
                if unit == activeDelimiter { delimiter = nil }
                index += 1
                continue
            }
            if unit == 34 || unit == 39 {
                delimiter = unit
                index += 1
                continue
            }
            if unit == 59 || unit == 64 { // ; and @ are assembly comment markers
                return NSRange(location: index, length: end - index)
            }
            if unit == 47, index + 1 < end, text.character(at: index + 1) == 47 {
                return NSRange(location: index, length: end - index)
            }
            index += 1
        }
        return nil
    }

    private func appendMatches(
        _ regex: NSRegularExpression,
        in line: String,
        base: Int,
        category: SyntaxCategory,
        to tokens: inout [SyntaxToken]
    ) {
        let range = NSRange(location: 0, length: (line as NSString).length)
        for match in regex.matches(in: line, range: range) {
            tokens.append(SyntaxToken(
                range: NSRange(location: base + match.range.location, length: match.range.length),
                category: category
            ))
        }
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

    private static func contentRange(of lineRange: NSRange, in text: NSString) -> NSRange {
        var length = lineRange.length
        while length > 0 {
            let unit = text.character(at: lineRange.location + length - 1)
            guard unit == 10 || unit == 13 else { break }
            length -= 1
        }
        return NSRange(location: lineRange.location, length: length)
    }
}
