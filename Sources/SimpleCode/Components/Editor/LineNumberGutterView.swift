import AppKit

/// The line-number gutter, implemented as a classic `NSRulerView` attached to the
/// text view's enclosing scroll view. This technique predates TextKit 2 and works
/// the same way regardless of which TextKit generation the client view uses.
///
/// Line geometry is read through TextKit 2's `NSTextLayoutManager`:
///   - `textLayoutFragment(for:)` locates the first visible line cheaply (an O(1)-ish
///     point query, not a scan from the document start).
///   - `enumerateTextLayoutFragments(from:options:)` then walks forward only across
///     the lines actually on screen.
/// Both APIs have existed since TextKit 2 shipped and are fully available on macOS
/// 26 — this file deliberately does not use the macOS 27 viewport-layout-controller
/// delegate conformance described in the architecture report as a future
/// enhancement (see the note at the bottom of this file).
final class LineNumberGutterView: NSRulerView {
    private weak var codeTextView: CodeTextView?
    var lineStartIndex = LineStartIndex()

    init(codeTextView: CodeTextView, scrollView: NSScrollView) {
        self.codeTextView = codeTextView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        ruleThickness = 44
        clientView = codeTextView
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("LineNumberGutterView does not support NSCoder")
    }

    func invalidate() {
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in dirtyRect: NSRect) {
        ColorRole.editorBackgroundNSColor.setFill()
        dirtyRect.fill()

        guard let codeTextView,
              let layoutManager = codeTextView.textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let scrollView = self.scrollView else { return }

        let visibleRect = scrollView.contentView.bounds
        let inset = codeTextView.textContainerInset

        let topPoint = CGPoint(x: 1, y: max(0, visibleRect.minY))
        guard let startFragment = layoutManager.textLayoutFragment(for: topPoint) else { return }
        let startLocation = startFragment.rangeInElement.location

        let startOffset = contentManager.offset(from: contentManager.documentRange.location, to: startLocation)
        var lineNumber = startOffset >= 0
            ? lineStartIndex.lineNumber(atUTF16Offset: startOffset)
            : 1

        let currentLineLocation = currentSelectionLocation(layoutManager: layoutManager)

        layoutManager.enumerateTextLayoutFragments(from: startLocation, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            guard frame.minY < visibleRect.maxY else { return false }

            let isCurrent = currentLineLocation.map { fragment.rangeInElement.contains($0) } ?? false
            draw(lineNumber: lineNumber, fragmentFrame: frame, visibleRect: visibleRect, inset: inset, isCurrent: isCurrent)

            lineNumber += 1
            return true
        }
    }

    private func currentSelectionLocation(layoutManager: NSTextLayoutManager) -> NSTextLocation? {
        layoutManager.textSelections.first?.textRanges.first?.location
    }

    private func draw(lineNumber: Int, fragmentFrame: CGRect, visibleRect: NSRect, inset: NSSize, isCurrent: Bool) {
        let numberString = "\(lineNumber)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: isCurrent ? .semibold : .regular),
            .foregroundColor: isCurrent ? ColorRole.editorLineNumberEmphasizedNSColor : ColorRole.editorLineNumberNSColor
        ]

        let size = numberString.size(withAttributes: attributes)
        let y = fragmentFrame.minY - visibleRect.minY + inset.height
        let x = ruleThickness - size.width - 8
        numberString.draw(at: NSPoint(x: max(4, x), y: y), withAttributes: attributes)
    }
}

// Future macOS 27 enhancement (documented, not implemented here): once macOS 27 is
// the effective minimum, `CodeTextView` could adopt the public
// `NSTextViewportLayoutControllerDelegate` conformance shown in WWDC26 session 370
// ("Elevate your app's text experience with TextKit") to receive `willLayout` /
// `configureRenderingSurface` / `didLayout` callbacks directly, removing the need for
// this ruler view to re-derive the visible range on every redraw. That API does not
// exist in the macOS 26 SDK this phase builds against, so it is not referenced here.
