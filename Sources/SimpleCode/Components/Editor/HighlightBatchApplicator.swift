import AppKit

enum HighlightParseStrategy {
    case incremental
    case full
}

/// Shared stale-result guard for syntax highlighting batches.
enum HighlightBatchApplicator {
    static func shouldApply(batchRevision: Int, currentRevision: Int) -> Bool {
        batchRevision == currentRevision
    }

    /// An incremental edit is valid only when the parser is known to represent
    /// the immediately preceding document revision. Any missed revision means
    /// its tree offsets may no longer describe the current source, so rebuild it.
    static func parseStrategy(
        lastParsedRevision: Int?,
        requestedRevision: Int
    ) -> HighlightParseStrategy {
        guard let lastParsedRevision,
              requestedRevision == lastParsedRevision + 1 else {
            return .full
        }
        return .incremental
    }

    /// Applies one semantic batch as a single text-storage transaction. Covered
    /// ranges return to the base foreground before tokens are painted so removed
    /// captures cannot leave stale colors behind, while unrelated ranges remain
    /// untouched.
    @MainActor
    static func apply(_ batch: HighlightBatch, to textStorage: NSTextStorage) {
        textStorage.beginEditing()
        for range in batch.coveredRanges where isValid(range, in: textStorage) {
            textStorage.addAttribute(
                .foregroundColor,
                value: ColorRole.editorForegroundNSColor,
                range: range
            )
        }
        for token in batch.tokens where isValid(token.range, in: textStorage) {
            let storedPair = SettingsColorResolver.appearance.syntaxPalette.pair(for: token.category)
            textStorage.addAttribute(
                .foregroundColor,
                value: storedPair.colorRolePair.dynamic,
                range: token.range
            )
        }
        textStorage.endEditing()
    }

    private static func isValid(_ range: NSRange, in textStorage: NSTextStorage) -> Bool {
        range.location != NSNotFound
            && range.location >= 0
            && range.length >= 0
            && NSMaxRange(range) <= textStorage.length
    }
}
