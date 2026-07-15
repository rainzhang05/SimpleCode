import AppKit

/// A noninteractive gutter drawn over the text view's reserved leading inset.
///
/// This deliberately is not an `NSRulerView`: attaching an AppKit ruler to the
/// TextKit 2 scroll view takes a legacy rendering integration path. Line geometry
/// is instead read from TextKit 2 layout fragments, bounded to visible fragments.
///
/// The gutter view tracks `visibleRect.minX` so it stays pinned to the leading
/// edge of the viewport while the document scrolls horizontally, avoiding paint
/// trails from document-relative drawing.
final class LineNumberGutterView: NSView {
    static let minimumWidth: CGFloat = 42

    private weak var codeTextView: CodeTextView?
    var lineStartIndex = LineStartIndex()
    private(set) var width: CGFloat = minimumWidth

        init(codeTextView: CodeTextView) {
        self.codeTextView = codeTextView
        let height = codeTextView.bounds.height > 0 ? codeTextView.bounds.height : codeTextView.frame.height
        super.init(frame: NSRect(
            x: 0,
            y: 0,
            width: Self.minimumWidth,
            height: max(height, 1)
        ))
        autoresizingMask = [.height]
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("LineNumberGutterView does not support NSCoder")
    }

    override var isOpaque: Bool { true }
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func accessibilityIsIgnored() -> Bool {
        true
    }

    func invalidate() {
        needsDisplay = true
    }

    /// Keeps the gutter pinned to the viewport's leading edge as the document
    /// scrolls. Changing the frame invalidates the previous and new regions so
    /// old digit paint cannot smear across the editor.
    func syncFrame(to textView: CodeTextView) {
        let viewportMinX: CGFloat
        if textView.enclosingScrollView != nil {
            let visibleMinX = textView.visibleRect.minX
            viewportMinX = visibleMinX.isFinite ? visibleMinX : 0
        } else {
            // Standalone text views report an unreliable visibleRect.
            viewportMinX = 0
        }
        let height = textView.bounds.height.isFinite && textView.bounds.height > 0
            ? textView.bounds.height
            : max(textView.frame.height, 1)
        let newFrame = NSRect(
            x: viewportMinX,
            y: textView.bounds.minY.isFinite ? textView.bounds.minY : 0,
            width: width,
            height: height
        )
        guard !frame.equalTo(newFrame) else { return }
        frame = newFrame
    }

    /// Returns `true` when the reserved editor inset needs to be laid out again.
    /// Tracking the editor one point smaller and using a digit-aware width keeps
    /// the gutter stable for small files while still accommodating five-plus digit
    /// line numbers without overlapping code.
    @discardableResult
    func updateMetrics(font: NSFont?, lineCount: Int) -> Bool {
        let pointSize = Self.lineNumberPointSize(editorFont: font)
        let digitFont = NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: .regular)
        let digitWidth = ("0" as NSString).size(withAttributes: [.font: digitFont]).width
        let digitCount = max(2, String(max(1, lineCount)).count)
        let proposedWidth = max(Self.minimumWidth, ceil(digitWidth * CGFloat(digitCount) + 18))
        guard abs(proposedWidth - width) > 0.5 else { return false }
        width = proposedWidth
        if let codeTextView {
            syncFrame(to: codeTextView)
        }
        needsDisplay = true
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let codeTextView,
              let layoutManager = codeTextView.textLayoutManager,
              let contentManager = layoutManager.textContentManager else { return }

        let visibleRect = codeTextView.visibleRect
        ColorRole.gutterBackgroundNSColor.setFill()
        bounds.intersection(dirtyRect).fill()

        let dirtyTextRect = codeTextView.convert(dirtyRect, from: self).intersection(visibleRect)
        guard !dirtyTextRect.isEmpty else { return }

        drawCurrentLineHighlight(
            from: codeTextView,
            dirtyRect: dirtyRect
        )

        let origin = codeTextView.textContainerOrigin
        let topPoint = EditorTextGeometry.layoutPoint(
            forViewPoint: CGPoint(
                x: EditorTextGeometry.textLookupX(in: codeTextView),
                y: max(origin.y, dirtyTextRect.minY)
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

        let pointSize = Self.lineNumberPointSize(editorFont: codeTextView.font)
        let normalFont = NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: .regular)
        let currentFont = NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: .semibold)
        let normalAttributes: [NSAttributedString.Key: Any] = [
            .font: normalFont,
            .foregroundColor: ColorRole.editorLineNumberNSColor
        ]
        let currentAttributes: [NSAttributedString.Key: Any] = [
            .font: currentFont,
            .foregroundColor: ColorRole.editorLineNumberEmphasizedNSColor
        ]

        layoutManager.enumerateTextLayoutFragments(from: startFragment.rangeInElement.location, options: [.ensuresLayout]) { fragment in
            guard let frame = EditorTextGeometry.visualLineFrame(
                in: fragment,
                textView: codeTextView
            ), let baseline = EditorTextGeometry.visualLineBaseline(
                in: fragment,
                textView: codeTextView
            ) else { return true }
            guard frame.minY < dirtyTextRect.maxY else { return false }

            let offset = contentManager.offset(
                from: contentManager.documentRange.location,
                to: fragment.rangeInElement.location
            )
            guard offset >= 0 else { return true }

            let lineNumber = lineStartIndex.lineNumber(atUTF16Offset: offset)
            draw(
                lineNumber: lineNumber,
                baseline: baseline,
                font: currentLineNumber == lineNumber ? currentFont : normalFont,
                attributes: currentLineNumber == lineNumber ? currentAttributes : normalAttributes,
                from: codeTextView
            )
            return true
        }
    }

    private func draw(
        lineNumber: Int,
        baseline: CGFloat,
        font: NSFont,
        attributes: [NSAttributedString.Key: Any],
        from codeTextView: CodeTextView
    ) {
        let numberString = "\(lineNumber)" as NSString
        let size = numberString.size(withAttributes: attributes)
        let y = convert(
            NSPoint(x: 0, y: baseline - font.ascender),
            from: codeTextView
        ).y
        numberString.draw(at: NSPoint(x: max(4, width - size.width - 8), y: y), withAttributes: attributes)
    }

    private func drawCurrentLineHighlight(
        from codeTextView: CodeTextView,
        dirtyRect: NSRect
    ) {
        guard let editorRect = codeTextView.currentLineHighlightRect() else { return }
        let highlightRect = convert(editorRect, from: codeTextView)
        let paintRect = highlightRect.intersection(bounds).intersection(dirtyRect)
        guard !paintRect.isEmpty else { return }

        ColorRole.editorCurrentLineNSColor.setFill()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(
            roundedRect: highlightRect,
            xRadius: CodeTextView.currentLineHighlightCornerRadius,
            yRadius: CodeTextView.currentLineHighlightCornerRadius
        ).addClip()
        paintRect.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func lineNumberPointSize(editorFont: NSFont?) -> CGFloat {
        (editorFont?.pointSize ?? 13) - 1
    }
}
