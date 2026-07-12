import AppKit

/// Converts between TextKit layout coordinates and the text view's document-view
/// coordinates. Keeping this math shared prevents the gutter, current-line paint,
/// and viewport highlighter from drifting by the text-container inset.
@MainActor
enum EditorTextGeometry {
    static func viewFrame(for layoutFrame: NSRect, in textView: NSTextView) -> NSRect {
        let origin = textView.textContainerOrigin
        return layoutFrame.offsetBy(dx: origin.x, dy: origin.y)
    }

    static func layoutPoint(forViewPoint viewPoint: NSPoint, in textView: NSTextView) -> NSPoint {
        let origin = textView.textContainerOrigin
        return NSPoint(x: viewPoint.x - origin.x, y: viewPoint.y - origin.y)
    }

    static func textLookupX(in textView: NSTextView) -> CGFloat {
        textView.textContainerOrigin.x + (textView.textContainer?.lineFragmentPadding ?? 0)
    }
}

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

        let visibleRect = textView.visibleRect
        let documentLength = textView.string.utf16.count
        guard documentLength > 0 else { return NSRange(location: 0, length: 0) }

        let origin = textView.textContainerOrigin
        let lookupX = EditorTextGeometry.textLookupX(in: textView)
        let topPoint = EditorTextGeometry.layoutPoint(
            forViewPoint: CGPoint(x: lookupX, y: max(origin.y, visibleRect.minY)),
            in: textView
        )
        let bottomPoint = EditorTextGeometry.layoutPoint(
            forViewPoint: CGPoint(x: lookupX, y: max(origin.y, visibleRect.maxY - 1)),
            in: textView
        )
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
