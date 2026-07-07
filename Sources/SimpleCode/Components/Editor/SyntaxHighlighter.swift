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

/// Shared syntax-highlighting surface for tree-sitter and pattern-based highlighters.
protocol SyntaxHighlighter: Actor {
    func load(text: String, revision: Int) async -> HighlightBatch
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
