import AppKit

/// The native text-editing surface, bridged into SwiftUI by `CodeEditorRepresentable`.
///
/// Responsibility owned by this file: configuring `NSTextView`/TextKit for code
/// editing (plain-text semantics, monospaced font, non-wrapping horizontally
/// scrollable layout, current-line highlighting) and nothing else — it has no
/// knowledge of SwiftTreeSitter, document sessions, or SwiftUI. Syntax
/// highlighting and document-model bookkeeping live in `CodeEditorRepresentable`'s
/// coordinator, which owns this view via `NSViewRepresentable`.
///
/// Uses one explicit TextKit 2 stack (`NSTextContentStorage` →
/// `NSTextLayoutManager` → `NSTextContainer`) so the view, session storage, and
/// layout APIs always agree on the same text system.
final class CodeTextView: NSTextView {
    private static let textInset = NSSize(width: 6, height: 8)

    /// Convenience initializer that asks AppKit to create its TextKit 2 graph.
    /// `init(frame:textContainer:)` always creates a legacy layout manager, even
    /// when passed a TextKit 2 container, so it cannot be used here.
    convenience init() {
        self.init(usingTextLayoutManager: true)
        configureForCodeEditing()
    }

    /// `true` when this view is backed by TextKit 2 (`NSTextLayoutManager`).
    var isUsingTextKit2: Bool {
        textLayoutManager != nil
    }

    var highlightCurrentLine = true
    weak var commandDelegate: CodeTextViewCommandDelegate?
    private var isPerformingPaste = false
    private weak var documentUndoManager: UndoManager?

    override var undoManager: UndoManager? {
        documentUndoManager ?? super.undoManager
    }

    func attachUndoManager(_ undoManager: UndoManager) {
        documentUndoManager = undoManager
    }

    func configureWordWrap(enabled: Bool, in scrollView: NSScrollView) {
        if enabled {
            isHorizontallyResizable = false
            textContainer?.widthTracksTextView = true
            textContainer?.containerSize = CGSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            maxSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        } else {
            isHorizontallyResizable = true
            textContainer?.widthTracksTextView = false
            textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        textLayoutManager?.textViewportLayoutController.layoutViewport()
    }

    /// Reserves a layout-only strip for the line-number subview. The gutter is not
    /// an `NSRulerView`, so this inset is what prevents its drawing from ever
    /// overlapping glyphs.
    func configureLineNumberGutter(visible: Bool, width: CGFloat = LineNumberGutterView.minimumWidth) {
        let insetWidth = visible ? width + Self.textInset.width : Self.textInset.width
        guard textContainerInset.width != insetWidth else { return }
        textContainerInset = NSSize(width: insetWidth, height: Self.textInset.height)
        textLayoutManager?.textViewportLayoutController.layoutViewport()
        needsDisplay = true
    }

    private func configureForCodeEditing() {
        // Plain-text semantics: no user-driven rich text formatting. This does not
        // prevent the app from programmatically coloring text for syntax
        // highlighting, which is independent of `isRichText`.
        isRichText = false
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        smartInsertDeleteEnabled = false
        usesFindPanel = false
        usesRuler = false
        // Non-wrapping layout with both vertical and horizontal scrolling — the
        // classic AppKit recipe for a code editor (word wrap is a deferred setting).
        isHorizontallyResizable = true
        isVerticallyResizable = true
        autoresizingMask = [.width, .height]
        textContainer?.widthTracksTextView = false
        textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        textContainerInset = Self.textInset
        drawsBackground = true
        backgroundColor = ColorRole.editorBackgroundNSColor
        textColor = ColorRole.editorForegroundNSColor
        insertionPointColor = ColorRole.editorForegroundNSColor
        selectedTextAttributes = [.backgroundColor: ColorRole.editorSelectionNSColor]
    }

    // MARK: Current-line highlight

    static let currentLineHighlightCornerRadius: CGFloat = 7

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawCurrentLineHighlight(in: rect)
    }

    private func drawCurrentLineHighlight(in dirtyRect: NSRect) {
        guard let highlightRect = currentLineHighlightRect() else { return }
        let paintRect = highlightRect.intersection(dirtyRect)
        guard !paintRect.isEmpty else { return }

        ColorRole.editorCurrentLineNSColor.setFill()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(
            roundedRect: highlightRect,
            xRadius: Self.currentLineHighlightCornerRadius,
            yRadius: Self.currentLineHighlightCornerRadius
        ).addClip()
        paintRect.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    func currentLineHighlightRect() -> NSRect? {
        guard highlightCurrentLine else { return nil }
        guard selectedRange().length == 0 else { return nil }
        guard let layoutManager = textLayoutManager,
              let selectionRange = layoutManager.textSelections.first?.textRanges.first else { return nil }

        var viewRect: NSRect?
        if let fragment = layoutManager.textLayoutFragment(for: selectionRange.location) {
            viewRect = EditorTextGeometry.visualLineFrame(in: fragment, textView: self)
        } else if let contentManager = layoutManager.textContentManager,
                  selectionRange.location.compare(contentManager.documentRange.endLocation) == .orderedSame {
            layoutManager.enumerateTextLayoutFragments(
                from: contentManager.documentRange.endLocation,
                options: [.reverse, .ensuresLayout]
            ) { fragment in
                viewRect = EditorTextGeometry.trailingEmptyLineFrame(in: fragment, textView: self)
                    ?? EditorTextGeometry.visualLineFrame(in: fragment, textView: self)
                return false
            }
        }

        guard var viewRect else { return nil }
        let visible = visibleRect
        let horizontalMin = max(visible.minX, bounds.minX)
        let horizontalMax = min(visible.maxX, bounds.maxX)
        viewRect.origin.x = horizontalMin
        viewRect.size.width = max(0, horizontalMax - horizontalMin)
        let highlightRect = viewRect.insetBy(dx: 4, dy: 0)
        return highlightRect.isEmpty ? nil : highlightRect
    }

    // MARK: Cursor

    /// NSTextView receives `mouseMoved` as first responder and sets the I-beam
    /// cursor even when the pointer is over an overlay (terminal panel,
    /// sidebar). Only let it manage the cursor when the pointer is actually
    /// over this view.
    override func mouseMoved(with event: NSEvent) {
        guard let contentView = window?.contentView else {
            super.mouseMoved(with: event)
            return
        }
        let point = contentView.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
        let hitView = contentView.hitTest(point)
        guard hitView === self || hitView?.isDescendant(of: self) == true else { return }
        super.mouseMoved(with: event)
    }

    // MARK: Editor commands

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isUndoShortcut = event.charactersIgnoringModifiers?.lowercased() == "z"
            && modifiers.subtracting([.command, .shift]).isEmpty
            && modifiers.contains(.command)
        guard isUndoShortcut else { return super.performKeyEquivalent(with: event) }

        if modifiers.contains(.shift) {
            guard undoManager?.canRedo == true else { return true }
            undoManager?.redo()
        } else {
            guard undoManager?.canUndo == true else { return true }
            undoManager?.undo()
        }
        return true
    }

    override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText() else {
            super.insertNewline(sender)
            return
        }
        if commandDelegate?.codeTextViewHandleReturn(self) == true { return }
        super.insertNewline(sender)
    }

    override func insertTab(_ sender: Any?) {
        guard !hasMarkedText() else {
            super.insertTab(sender)
            return
        }
        if commandDelegate?.codeTextViewHandleTab(self, shift: false) == true { return }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        guard !hasMarkedText() else {
            super.insertBacktab(sender)
            return
        }
        if commandDelegate?.codeTextViewHandleTab(self, shift: true) == true { return }
        super.insertBacktab(sender)
    }

    override func deleteBackward(_ sender: Any?) {
        guard !hasMarkedText() else {
            super.deleteBackward(sender)
            return
        }
        if commandDelegate?.codeTextViewHandleDeleteBackward(self) == true { return }
        super.deleteBackward(sender)
    }

    override func moveToBeginningOfLine(_ sender: Any?) {
        guard !hasMarkedText() else {
            super.moveToBeginningOfLine(sender)
            return
        }
        if commandDelegate?.codeTextViewHandleMoveToBeginningOfLine(self, extendSelection: false) == true { return }
        super.moveToBeginningOfLine(sender)
    }

    override func moveToBeginningOfLineAndModifySelection(_ sender: Any?) {
        guard !hasMarkedText() else {
            super.moveToBeginningOfLineAndModifySelection(sender)
            return
        }
        if commandDelegate?.codeTextViewHandleMoveToBeginningOfLine(self, extendSelection: true) == true { return }
        super.moveToBeginningOfLineAndModifySelection(sender)
    }

    override func insertText(_ insertString: Any) {
        handleInsertText(insertString, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        handleInsertText(insertString, replacementRange: replacementRange)
    }

    override func paste(_ sender: Any?) {
        // A one-character paste must remain a literal paste, not turn into an
        // auto-closing pair. Keeping the native paste transaction also preserves
        // macOS undo grouping and pasteboard semantics.
        isPerformingPaste = true
        defer { isPerformingPaste = false }
        super.paste(sender)
    }

    private func handleInsertText(_ insertString: Any, replacementRange: NSRange) {
        guard !hasMarkedText() else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }
        if !isPerformingPaste,
           let string = insertString as? String,
           string.count == 1,
           let character = string.first,
           commandDelegate?.codeTextView(self, shouldInsertCharacter: character) == true {
            return
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }
}
