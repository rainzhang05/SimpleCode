import Foundation

/// A single text-storage edit, expressed in UTF-16 code-unit offsets (matching
/// `NSString`/`NSTextStorage`). Converted to tree-sitter's UTF-16LE byte offsets
/// (`offset * 2`) inside tree-sitter highlighters.
struct TextEditDescriptor: Sendable {
    let startUTF16: Int
    let oldEndUTF16: Int
    let newEndUTF16: Int
}

/// A batch of syntax tokens tagged with the document revision that produced them, so
/// a caller can reject it if a newer edit has since arrived. `coveredRanges` is the
/// full span(s) that were queried (not just the ranges that happened to match a
/// capture) — the caller resets exactly these ranges to the default foreground color
/// before applying `tokens`, so text that no longer matches any capture (e.g. a
/// deleted keyword) doesn't keep a stale color.
struct HighlightBatch: Sendable {
    let revision: Int
    let coveredRanges: [NSRange]
    let tokens: [SyntaxToken]
}

struct InitialHighlightCursor: Equatable, Sendable {
    let generation: UInt64
    let revision: Int
    let remainingRanges: [NSRange]
}

struct InitialHighlightPage: Sendable {
    let batch: HighlightBatch
    let next: InitialHighlightCursor?
}

enum InitialHighlightPaging {
    static let pageSizeUTF16 = 65_536
    static let backgroundPageSizeUTF16 = 16_384

    static func priorityRange(in text: String, aroundUTF16Offset offset: Int) -> NSRange {
        let string = text as NSString
        guard string.length > pageSizeUTF16 else {
            return NSRange(location: 0, length: string.length)
        }

        let requestedOffset = max(0, min(string.length - 1, offset))
        let centeredStart = max(
            0,
            min(string.length - pageSizeUTF16, requestedOffset - pageSizeUTF16 / 4)
        )
        let lineStart = string.lineRange(for: NSRange(location: centeredStart, length: 0)).location
        // A minified or generated file can contain a single multi-megabyte line.
        // Pulling such a page back to the line start would exclude the requested
        // viewport, so keep a bounded centered window when no nearby boundary exists.
        let start = centeredStart - lineStart > pageSizeUTF16 / 2 ? centeredStart : lineStart
        let proposedEnd = min(string.length, start + pageSizeUTF16)
        guard proposedEnd < string.length else {
            return NSRange(location: start, length: string.length - start)
        }
        let containingLine = string.lineRange(for: NSRange(location: proposedEnd, length: 0))
        let lineBoundary = containingLine.location
        let end = lineBoundary > start ? lineBoundary : proposedEnd
        return NSRange(location: start, length: end - start)
    }

    static func remainingRanges(documentLength: Int, excluding priorityRange: NSRange) -> [NSRange] {
        let priority = NSIntersectionRange(
            priorityRange,
            NSRange(location: 0, length: max(0, documentLength))
        )
        var ranges: [NSRange] = []
        let suffixStart = NSMaxRange(priority)
        if suffixStart < documentLength {
            ranges.append(NSRange(location: suffixStart, length: documentLength - suffixStart))
        }
        if priority.location > 0 {
            ranges.append(NSRange(location: 0, length: priority.location))
        }
        return ranges
    }

    static func nextPageRange(in text: String, cursor: InitialHighlightCursor, pageSizeUTF16: Int) -> NSRange? {
        guard let remaining = cursor.remainingRanges.first, remaining.length > 0 else { return nil }
        let string = text as NSString
        let requestedLength = min(max(1, pageSizeUTF16), remaining.length)
        guard requestedLength < remaining.length else { return remaining }
        let proposedEnd = remaining.location + requestedLength
        let containingLine = string.lineRange(for: NSRange(location: proposedEnd, length: 0))
        let lineBoundary = containingLine.location
        let end = lineBoundary > remaining.location ? lineBoundary : proposedEnd
        return NSRange(location: remaining.location, length: max(1, end - remaining.location))
    }

    static func advancing(_ cursor: InitialHighlightCursor, past pageRange: NSRange) -> InitialHighlightCursor? {
        guard let first = cursor.remainingRanges.first,
              first.location == pageRange.location,
              pageRange.length > 0,
              NSMaxRange(pageRange) <= NSMaxRange(first) else { return nil }
        var remaining = Array(cursor.remainingRanges.dropFirst())
        if NSMaxRange(pageRange) < NSMaxRange(first) {
            remaining.insert(
                NSRange(location: NSMaxRange(pageRange), length: NSMaxRange(first) - NSMaxRange(pageRange)),
                at: 0
            )
        }
        guard !remaining.isEmpty else { return nil }
        return InitialHighlightCursor(
            generation: cursor.generation,
            revision: cursor.revision,
            remainingRanges: remaining
        )
    }
}

/// Shared syntax-highlighting surface for tree-sitter and pattern-based highlighters.
protocol SyntaxHighlighter: Actor {
    func load(text: String, revision: Int) async -> HighlightBatch
    func prepareInitial(
        text: String,
        revision: Int,
        priorityUTF16Range: NSRange
    ) async -> InitialHighlightPage
    func continueInitial(
        _ cursor: InitialHighlightCursor,
        pageSizeUTF16: Int
    ) async -> InitialHighlightPage?
    func applyEdit(
        fullText: String,
        edit: TextEditDescriptor,
        revision: Int,
        priorityUTF16Range: NSRange
    ) async -> (priority: HighlightBatch, remainder: HighlightBatch?)
    func scheduleViewport(
        fullText: String,
        revision: Int,
        visibleUTF16Range: NSRange
    ) async -> (priority: HighlightBatch, remainder: HighlightBatch?)
}

extension SyntaxHighlighter {
    func prepareInitial(
        text: String,
        revision: Int,
        priorityUTF16Range: NSRange
    ) async -> InitialHighlightPage {
        InitialHighlightPage(batch: await load(text: text, revision: revision), next: nil)
    }

    func continueInitial(
        _ cursor: InitialHighlightCursor,
        pageSizeUTF16: Int
    ) async -> InitialHighlightPage? {
        nil
    }
}
