import AppKit

/// A noninteractive gutter drawn over the text view's reserved leading inset.
///
/// This deliberately is not an `NSRulerView`: attaching an AppKit ruler to the
/// TextKit 2 scroll view takes a legacy rendering integration path. Line geometry
/// is instead read from TextKit 2 layout fragments, bounded to visible fragments.
final class LineNumberGutterView: NSView {
    static let minimumWidth: CGFloat = 42

    private weak var codeTextView: CodeTextView?
    var lineStartIndex = LineStartIndex()
    private(set) var width: CGFloat = minimumWidth

    init(codeTextView: CodeTextView) {
        self.codeTextView = codeTextView
        super.init(frame: codeTextView.bounds)
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("LineNumberGutterView does not support NSCoder")
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func accessibilityIsIgnored() -> Bool {
        true
    }

    func invalidate() {
        needsDisplay = true
    }

    /// Returns `true` when the reserved editor inset needs to be laid out again.
    /// Matching the editor's point size and using a digit-aware width keeps the
    /// gutter stable for small files while still accommodating five-plus digit line
    /// numbers without overlapping code.
    @discardableResult
    func updateMetrics(font: NSFont?, lineCount: Int) -> Bool {
        let pointSize = max(10, (font?.pointSize ?? 13) - 1)
        let digitFont = NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: .regular)
        let digitWidth = ("0" as NSString).size(withAttributes: [.font: digitFont]).width
        let digitCount = max(2, String(max(1, lineCount)).count)
        let proposedWidth = max(Self.minimumWidth, ceil(digitWidth * CGFloat(digitCount) + 18))
        guard abs(proposedWidth - width) > 0.5 else { return false }
        width = proposedWidth
        needsDisplay = true
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let codeTextView,
              let layoutManager = codeTextView.textLayoutManager,
              let contentManager = layoutManager.textContentManager else { return }

        let visibleRect = codeTextView.visibleRect
        let gutterRect = convert(
            NSRect(
                x: visibleRect.minX,
                y: visibleRect.minY,
                width: width,
                height: visibleRect.height
            ),
            from: codeTextView
        )
        ColorRole.gutterBackgroundNSColor.setFill()
        gutterRect.intersection(dirtyRect).fill()

        let origin = codeTextView.textContainerOrigin
        let topPoint = EditorTextGeometry.layoutPoint(
            forViewPoint: CGPoint(
                x: EditorTextGeometry.textLookupX(in: codeTextView),
                y: max(origin.y, visibleRect.minY)
            ),
            in: codeTextView
        )
        guard let startFragment = layoutManager.textLayoutFragment(for: topPoint) else { return }

        let currentLineNumber: Int?
        if let location = layoutManager.textSelections.first?.textRanges.first?.location {
            let offset = contentManager.offset(from: contentManager.documentRange.location, to: location)
            currentLineNumber = offset >= 0 ? lineStartIndex.lineNumber(atUTF16Offset: offset) : nil
        } else {
            currentLineNumber = nil
        }

        layoutManager.enumerateTextLayoutFragments(from: startFragment.rangeInElement.location, options: [.ensuresLayout]) { fragment in
            let frame = EditorTextGeometry.viewFrame(for: fragment.layoutFragmentFrame, in: codeTextView)
            guard frame.minY < visibleRect.maxY else { return false }

            let offset = contentManager.offset(
                from: contentManager.documentRange.location,
                to: fragment.rangeInElement.location
            )
            guard offset >= 0 else { return true }

            let lineNumber = lineStartIndex.lineNumber(atUTF16Offset: offset)
            draw(
                lineNumber: lineNumber,
                fragmentFrame: frame,
                visibleRect: visibleRect,
                isCurrent: currentLineNumber == lineNumber
            )
            return true
        }
    }

    private func draw(lineNumber: Int, fragmentFrame: CGRect, visibleRect: NSRect, isCurrent: Bool) {
        let numberString = "\(lineNumber)" as NSString
        let pointSize = max(10, (codeTextView?.font?.pointSize ?? 13) - 1)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: isCurrent ? .semibold : .regular),
            .foregroundColor: isCurrent ? ColorRole.editorLineNumberEmphasizedNSColor : ColorRole.editorLineNumberNSColor
        ]

        let size = numberString.size(withAttributes: attributes)
        guard let codeTextView else { return }
        let textPoint = NSPoint(
            x: visibleRect.minX + width - size.width - 8,
            y: fragmentFrame.midY - size.height / 2
        )
        let point = convert(textPoint, from: codeTextView)
        numberString.draw(at: NSPoint(x: max(4, point.x), y: point.y), withAttributes: attributes)
    }
}
