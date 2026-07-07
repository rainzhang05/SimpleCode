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
/// TextKit decision: this view is constructed with an explicit TextKit 2 stack
/// (`NSTextContentStorage` → `NSTextLayoutManager` → `NSTextContainer`), which is
/// fully supported on macOS 26. No macOS 27-only API is used. See
/// `TechnicalSpikes/EditorSpikeNotes.md` for the verification that TextKit 2 is
/// active at runtime and for the (none encountered) blockers.
final class CodeTextView: NSTextView {
    /// Convenience initializer that builds the TextKit 2 object graph explicitly,
    /// rather than relying on whichever default `NSTextView()` happens to pick.
    convenience init() {
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        contentStorage.addTextLayoutManager(layoutManager)

        let container = NSTextContainer(size: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        layoutManager.textContainer = container

        self.init(frame: .zero, textContainer: container)
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configureForCodeEditing()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureForCodeEditing()
    }

    /// `true` when this view ended up backed by TextKit 2 (`NSTextLayoutManager`).
    /// Used by the technical spike to log verifiable evidence rather than assume.
    var isUsingTextKit2: Bool {
        textLayoutManager != nil
    }

    var highlightCurrentLine = true
    weak var commandDelegate: CodeTextViewCommandDelegate?
    var bracketPair: (open: Int, close: Int)?

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

        textContainerInset = NSSize(width: 6, height: 8)
        drawsBackground = true
        backgroundColor = ColorRole.editorBackgroundNSColor
        textColor = ColorRole.editorForegroundNSColor
        insertionPointColor = ColorRole.editorForegroundNSColor
        selectedTextAttributes = [.backgroundColor: ColorRole.editorSelectionNSColor]
    }

    // MARK: Current-line highlight

    /// Drawn *before* calling `super.draw`, so glyphs are painted on top of the
    /// highlight rather than being obscured by it.
    override func draw(_ dirtyRect: NSRect) {
        drawCurrentLineHighlight()
        drawBracketHighlight()
        super.draw(dirtyRect)
    }

    private func drawBracketHighlight() {
        guard let bracketPair else { return }
        BracketHighlightRenderer.drawBracketPair(in: self, openLocation: bracketPair.open, closeLocation: bracketPair.close)
    }

    private func drawCurrentLineHighlight() {
        guard highlightCurrentLine else { return }
        guard let layoutManager = textLayoutManager else { return }
        guard let selectionRange = layoutManager.textSelections.first?.textRanges.first else { return }

        // The first fragment at/after the caret's location is the line the caret is
        // on; we only need its frame, so the enumeration stops immediately.
        var lineFrame: NSRect?
        layoutManager.enumerateTextLayoutFragments(from: selectionRange.location, options: [.ensuresLayout]) { fragment in
            lineFrame = fragment.layoutFragmentFrame
            return false
        }

        guard var rect = lineFrame else { return }
        rect.origin.x = 0
        rect.size.width = max(bounds.width, rect.size.width)

        ColorRole.editorCurrentLineNSColor.setFill()
        rect.fill()
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
