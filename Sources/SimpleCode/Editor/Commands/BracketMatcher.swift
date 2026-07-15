import Foundation

enum BracketMatcher {
    private static let openers: [UInt16: UInt16] = [
        40: 41,   // ( )
        91: 93,   // [ ]
        123: 125, // { }
    ]

    private static let closers: [UInt16: UInt16] = [
        41: 40,
        93: 91,
        125: 123,
    ]

    /// Maximum code units to scan in either direction from `location`.
    static let defaultScanBound = 10_000

    static func matchingBracket(
        at location: Int,
        in text: String,
        syntaxContext: SyntaxContext? = nil,
        scanBound: Int = defaultScanBound
    ) -> Int? {
        let ns = EditorTextSupport.nsString(text)
        guard location >= 0, location < ns.length else { return nil }

        let char = ns.character(at: location)
        if let closer = openers[char] {
            return scanForward(
                from: location,
                opener: char,
                closer: closer,
                in: text,
                syntaxContext: syntaxContext,
                scanBound: scanBound
            )
        }
        if let opener = closers[char] {
            return scanBackward(
                from: location,
                opener: opener,
                closer: char,
                in: text,
                syntaxContext: syntaxContext,
                scanBound: scanBound
            )
        }
        return nil
    }

    private static func scanForward(
        from start: Int,
        opener: UInt16,
        closer: UInt16,
        in text: String,
        syntaxContext: SyntaxContext?,
        scanBound: Int
    ) -> Int? {
        let ns = EditorTextSupport.nsString(text)
        var depth = 0
        let end = min(ns.length, start + scanBound)
        var index = start
        while index < end {
            if let ctx = syntaxContext, ctx.isInsideSpecialToken(at: index) {
                index = skipToken(at: index, context: ctx) ?? (index + 1)
                continue
            }
            let ch = ns.character(at: index)
            if ch == opener {
                depth += 1
            } else if ch == closer {
                depth -= 1
                if depth == 0 { return index }
            }
            index += 1
        }
        return nil
    }

    private static func scanBackward(
        from start: Int,
        opener: UInt16,
        closer: UInt16,
        in text: String,
        syntaxContext: SyntaxContext?,
        scanBound: Int
    ) -> Int? {
        let ns = EditorTextSupport.nsString(text)
        var depth = 0
        let begin = max(0, start - scanBound)
        var index = start
        while index >= begin {
            if let ctx = syntaxContext, ctx.isInsideSpecialToken(at: index) {
                index = (skipTokenBackward(at: index, context: ctx) ?? (index - 1))
                if index < begin { break }
                continue
            }
            let ch = ns.character(at: index)
            if ch == closer {
                depth += 1
            } else if ch == opener {
                depth -= 1
                if depth == 0 { return index }
            }
            if index == 0 { break }
            index -= 1
        }
        return nil
    }

    private static func skipToken(at location: Int, context: SyntaxContext) -> Int? {
        for range in context.stringRanges where NSLocationInRange(location, range) {
            return range.location + range.length
        }
        for range in context.commentRanges where NSLocationInRange(location, range) {
            return range.location + range.length
        }
        return nil
    }

    private static func skipTokenBackward(at location: Int, context: SyntaxContext) -> Int? {
        for range in context.stringRanges where NSLocationInRange(location, range) {
            return range.location - 1
        }
        for range in context.commentRanges where NSLocationInRange(location, range) {
            return range.location - 1
        }
        return nil
    }
}
