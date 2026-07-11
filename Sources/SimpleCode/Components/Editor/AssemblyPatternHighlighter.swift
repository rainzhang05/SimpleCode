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
        if cachedRevision != revision || cachedText != fullText {
            let batch = await load(text: fullText, revision: revision)
            let visibleTokens = batch.tokens.filter { NSIntersectionRange($0.range, visibleUTF16Range).length > 0 }
            let priority = HighlightBatch(revision: revision, coveredRanges: [visibleUTF16Range], tokens: visibleTokens)
            return (priority, nil)
        }

        let visibleTokens = cachedTokens.filter { NSIntersectionRange($0.range, visibleUTF16Range).length > 0 }
        let priority = HighlightBatch(revision: revision, coveredRanges: [visibleUTF16Range], tokens: visibleTokens)
        return (priority, nil)
    }

    private func highlightEntireDocument(_ text: String) -> [SyntaxToken] {
        let lineCount = max(1, text.split(separator: "\n", omittingEmptySubsequences: false).count)
        return highlightLines(in: text, lineRange: 1...lineCount)
    }

    private func highlightLines(in text: String, lineRange: ClosedRange<Int>) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []
        var lineNumber = 1
        var lineStart = text.startIndex

        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = String(text[lineStart..<lineEnd])

            if lineRange.contains(lineNumber) {
                let baseUTF16 = text.utf16.distance(from: text.utf16.startIndex, to: lineStart.samePosition(in: text.utf16)!)
                tokens.append(contentsOf: highlightLine(line, baseUTF16Offset: baseUTF16))
            }

            if lineEnd == text.endIndex { break }
            lineStart = text.index(after: lineEnd)
            lineNumber += 1
        }

        return tokens
    }

    private func highlightLine(_ line: String, baseUTF16Offset: Int) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []
        let nsLine = line as NSString

        if let commentRange = commentRange(in: line) {
            tokens.append(SyntaxToken(
                range: NSRange(location: baseUTF16Offset + commentRange.location, length: commentRange.length),
                category: .comment
            ))
            return tokens
        }

        for match in labelMatches(in: line) {
            tokens.append(SyntaxToken(
                range: NSRange(location: baseUTF16Offset + match.range.location, length: match.range.length),
                category: .label
            ))
        }

        for match in directiveMatches(in: line) {
            tokens.append(SyntaxToken(
                range: NSRange(location: baseUTF16Offset + match.range.location, length: match.range.length),
                category: .preprocessor
            ))
        }

        for match in instructionMatches(in: line) {
            tokens.append(SyntaxToken(
                range: NSRange(location: baseUTF16Offset + match.range.location, length: match.range.length),
                category: .keyword
            ))
        }

        for match in registerMatches(in: line) {
            tokens.append(SyntaxToken(
                range: NSRange(location: baseUTF16Offset + match.range.location, length: match.range.length),
                category: .variable
            ))
        }

        for match in numberMatches(in: line) {
            tokens.append(SyntaxToken(
                range: NSRange(location: baseUTF16Offset + match.range.location, length: match.range.length),
                category: .number
            ))
        }

        for match in stringMatches(in: nsLine) {
            tokens.append(SyntaxToken(
                range: NSRange(location: baseUTF16Offset + match.location, length: match.length),
                category: .string
            ))
        }

        return tokens
    }

    private func commentRange(in line: String) -> NSRange? {
        let patterns = [#";.*$"#, #"#.*$"#, #"//.*$"#, #"@.*$"#]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                return match.range
            }
        }
        return nil
    }

    private func labelMatches(in line: String) -> [NSTextCheckingResult] {
        matches(for: #"(?i)^\s*([A-Za-z_.@][\w.$@]*)\s*:"#, in: line)
    }

    private func directiveMatches(in line: String) -> [NSTextCheckingResult] {
        matches(for: #"(?i)\.([A-Za-z_][\w.]*)"#, in: line)
    }

    private func instructionMatches(in line: String) -> [NSTextCheckingResult] {
        let intelATT = #"(?i)\b(mov|movq|movl|lea|add|sub|mul|div|and|or|xor|not|neg|inc|dec|push|pop|call|ret|jmp|je|jne|jz|jnz|cmp|test|nop|syscall|int|cli|sti|hlt|leave|enter|xorq|addq|subq|callq|retq)\b"#
        let aarch64 = #"(?i)\b(mov|movz|movk|add|sub|mul|madd|msub|and|orr|eor|lsl|lsr|asr|cmp|b|bl|br|ret|ldr|str|ldp|stp|adr|adrp|svc|nop)\b"#
        return matches(for: intelATT, in: line) + matches(for: aarch64, in: line)
    }

    private func registerMatches(in line: String) -> [NSTextCheckingResult] {
        let x86 = #"(?i)\b(%?(?:r(?:ax|bx|cx|dx|si|di|bp|sp|8|9|10|11|12|13|14|15)(?:d|w|b)?|e(?:ax|bx|cx|dx|si|di|bp|sp)|a(?:x|h|l)|b(?:x|h|l)|c(?:x|h|l)|d(?:x|h|l)|si|di|bp|sp|r\d+b?))\b"#
        let aarch64 = #"(?i)\b(x\d{1,2}|w\d{1,2}|sp|lr|pc|xzr|wzr)\b"#
        return matches(for: x86, in: line) + matches(for: aarch64, in: line)
    }

    private func numberMatches(in line: String) -> [NSTextCheckingResult] {
        matches(for: #"(?i)(?:\$|#)?0x[0-9a-f]+|\b\d+\b"#, in: line)
    }

    private func stringMatches(in line: NSString) -> [NSRange] {
        let ranges: [NSRange] = []
        let pattern = #""([^"\\]|\\.)*""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return ranges }
        let matches = regex.matches(in: line as String, range: NSRange(location: 0, length: line.length))
        return matches.map(\.range)
    }

    private func matches(for pattern: String, in line: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: line, range: NSRange(location: 0, length: (line as NSString).length))
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
