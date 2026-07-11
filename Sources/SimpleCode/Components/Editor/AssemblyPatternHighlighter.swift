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

    func load(text: String, revision: Int) async -> HighlightBatch {
        let tokens = highlight(text, restrictedTo: NSRange(location: 0, length: text.utf16.count))
        cachedText = text
        cachedRevision = revision
        cachedTokens = tokens
        return HighlightBatch(
            revision: revision,
            coveredRanges: [NSRange(location: 0, length: text.utf16.count)],
            tokens: tokens
        )
    }

    func applyEdit(
        fullText: String,
        edit: TextEditDescriptor,
        revision: Int,
        priorityUTF16Range: NSRange
    ) async -> (priority: HighlightBatch, remainder: HighlightBatch?) {
        guard cachedRevision == revision - 1 else {
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
        return (
            HighlightBatch(
                revision: revision,
                coveredRanges: visibleRanges,
                tokens: tokens(in: visibleRanges, from: cachedTokens)
            ),
            nil
        )
    }

    private func highlight(_ text: String, restrictedTo range: NSRange) -> [SyntaxToken] {
        let nsText = text as NSString
        guard nsText.length > 0, range.length > 0 else { return [] }
        var tokens: [SyntaxToken] = []
        var location = max(0, min(range.location, nsText.length))
        let end = min(nsText.length, NSMaxRange(range))

        while location < end {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
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

    private func lineRange(containingUTF16Edit edit: TextEditDescriptor, in text: String) -> ClosedRange<Int> {
        let editStart = max(0, edit.startUTF16)
        let editEnd = max(editStart, edit.newEndUTF16)
        let startLine = lineNumber(atUTF16Offset: editStart, in: text)
        let endLine = lineNumber(atUTF16Offset: max(editStart, editEnd - 1), in: text)
        return startLine...endLine
    }

    private func utf16Range(forLines lines: ClosedRange<Int>, in text: String) -> NSRange {
        var lineNumber = 1
        var lineStart = text.startIndex
        var rangeStart: Int?
        var rangeEnd = 0

        while lineStart <= text.endIndex {
            if lines.contains(lineNumber) {
                let offset = text.utf16.distance(from: text.utf16.startIndex, to: lineStart.samePosition(in: text.utf16) ?? text.utf16.endIndex)
                if rangeStart == nil { rangeStart = offset }
                let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
                rangeEnd = text.utf16.distance(from: text.utf16.startIndex, to: lineEnd.samePosition(in: text.utf16) ?? text.utf16.endIndex)
            }
            if lineStart == text.endIndex { break }
            if let lineEnd = text[lineStart...].firstIndex(of: "\n") {
                lineStart = text.index(after: lineEnd)
            } else {
                break
            }
            lineNumber += 1
        }

        let start = rangeStart ?? 0
        return NSRange(location: start, length: max(0, rangeEnd - start))
    }

    private func lineNumber(atUTF16Offset offset: Int, in text: String) -> Int {
        let clamped = max(0, min(offset, text.utf16.count))
        var line = 1
        var current = 0
        for unit in text.utf16 {
            if current >= clamped { break }
            if unit == 10 { line += 1 }
            current += 1
        }
        return line
    }
}
