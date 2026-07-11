import AppKit

/// Computes the UTF-16 character range currently visible in the editor scroll view,
/// expanded by a margin for syntax-highlight prioritization.
enum EditorVisibleRange {
    static let defaultMarginUTF16 = 1_000

    @MainActor
    static func visibleUTF16Range(
        in textView: CodeTextView,
        scrollView: NSScrollView,
        marginUTF16: Int = defaultMarginUTF16
    ) -> NSRange? {
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager else { return nil }

        let visibleRect = scrollView.contentView.bounds
        let documentLength = textView.string.utf16.count
        guard documentLength > 0 else { return NSRange(location: 0, length: 0) }

        let topPoint = CGPoint(x: 1, y: max(0, visibleRect.minY))
        let bottomPoint = CGPoint(x: 1, y: max(0, visibleRect.maxY - 1))
        guard let topFragment = layoutManager.textLayoutFragment(for: topPoint),
              let bottomFragment = layoutManager.textLayoutFragment(for: bottomPoint) else {
            return NSRange(location: 0, length: min(documentLength, marginUTF16 * 2))
        }

        let startOffset = contentManager.offset(
            from: contentManager.documentRange.location,
            to: topFragment.rangeInElement.location
        )
        let endOffset = contentManager.offset(
            from: contentManager.documentRange.location,
            to: bottomFragment.rangeInElement.endLocation
        )
        guard startOffset >= 0, endOffset >= startOffset else { return nil }

        let lower = max(0, startOffset - marginUTF16)
        let upper = min(documentLength, endOffset + marginUTF16)
        return NSRange(location: lower, length: upper - lower)
    }

    static func union(_ lhs: NSRange, _ rhs: NSRange, documentLength: Int) -> NSRange {
        let lower = max(0, min(lhs.location, rhs.location))
        let upper = min(documentLength, max(NSMaxRange(lhs), NSMaxRange(rhs)))
        return NSRange(location: lower, length: max(0, upper - lower))
    }
}
