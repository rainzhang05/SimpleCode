import Foundation

/// Line-oriented regex highlighter for common assembly dialects (x86 Intel, AT&T, AArch64).
actor AssemblyPatternHighlighter: SyntaxHighlighter {
    private var cachedText: String = ""
    private var cachedRevision: Int = -1
    private var cachedTokens: [SyntaxToken] = []

    func load(text: String, revision: Int) async -> HighlightBatch {
        let tokens = highlightEntireDocument(text)
        cachedText = text
        cachedRevision = revision
        cachedTokens = tokens
        let wholeDocument = NSRange(location: 0, length: text.utf16.count)
        return HighlightBatch(revision: revision, coveredRanges: [wholeDocument], tokens: tokens)
    }

    func applyEdit(
        fullText: String,
        edit: TextEditDescriptor,
        revision: Int,
        priorityUTF16Range: NSRange
    ) async -> (priority: HighlightBatch, remainder: HighlightBatch?) {
        let editPointRange = NSRange(location: edit.startUTF16, length: max(0, edit.newEndUTF16 - edit.startUTF16))
        let priorityRange = EditorVisibleRange.union(priorityUTF16Range, editPointRange, documentLength: fullText.utf16.count)

        if cachedRevision != revision - 1 || cachedText.isEmpty {
            let batch = await load(text: fullText, revision: revision)
            return (batch, nil)
        }

        let affectedLines = lineRange(containingUTF16Edit: edit, in: fullText)
        let priorityTokens = highlightLines(in: fullText, lineRange: affectedLines)
        let affectedUTF16Range = utf16Range(forLines: affectedLines, in: fullText)
        let priorityBatch = HighlightBatch(
            revision: revision,
            coveredRanges: [priorityRange],
            tokens: priorityTokens.filter { NSIntersectionRange($0.range, priorityRange).length > 0 }
        )

        cachedText = fullText
        cachedRevision = revision
        cachedTokens = highlightEntireDocument(fullText)

        let remainderBatch = HighlightBatch(
            revision: revision,
            coveredRanges: [affectedUTF16Range],
            tokens: priorityTokens
        )
        return (priorityBatch, remainderBatch)
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
