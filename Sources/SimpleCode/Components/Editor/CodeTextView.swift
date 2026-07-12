import AppKit

/// The native text-editing surface, bridged into SwiftUI by `CodeEditorRepresentable`.
///
/// Responsibility owned by this file: configuring `NSTextView`/TextKit for code
/// editing (plain-text semantics, monospaced font, non-wrapping horizontally
/// scrollable layout, current-line highlighting) and nothing else — it has no
/// knowledge of SwiftTreeSitter, `EditorDocumentModel`, or SwiftUI. Syntax
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

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawCurrentLineHighlight(in: rect)
    }

    private func drawCurrentLineHighlight(in dirtyRect: NSRect) {
        guard highlightCurrentLine else { return }
        guard selectedRange().length == 0 else { return }
        guard let layoutManager = textLayoutManager,
              let selectionRange = layoutManager.textSelections.first?.textRanges.first else { return }

        var fillRect: NSRect?
        layoutManager.enumerateTextLayoutFragments(from: selectionRange.location, options: [.ensuresLayout]) { fragment in
            fillRect = fragment.layoutFragmentFrame
            return false
        }

        guard let layoutRect = fillRect else { return }
        var viewRect = EditorTextGeometry.viewFrame(for: layoutRect, in: self)
        let visible = visibleRect
        viewRect.origin.x = visible.minX
        viewRect.size.width = visible.width
        let paintRect = viewRect.intersection(dirtyRect)
        guard !paintRect.isEmpty else { return }

        ColorRole.editorCurrentLineNSColor.setFill()
        paintRect.fill()
    }

    // MARK: Editor commands

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
