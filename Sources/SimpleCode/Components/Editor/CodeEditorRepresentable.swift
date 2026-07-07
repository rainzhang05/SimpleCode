import AppKit
import SwiftUI

struct CodeEditorRepresentable: NSViewRepresentable {
    var session: EditorDocumentSession
    var settings: AppSettingsStore
    var workspace: WorkspaceModel
    var onTextChanged: () -> Void

    private var fontSize: CGFloat { settings.editorFontSize }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, settings: settings, workspace: workspace, onTextChanged: onTextChanged)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CodeTextView()
        textView.delegate = context.coordinator
        textView.commandDelegate = context.coordinator
        textView.font = Typography.editorFont(
            family: settings.typography.editorFontFamily,
            size: fontSize,
            ligatures: settings.typography.editorFontLigatures
        )
        textView.isEditable = !session.isReadOnly

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.drawsBackground = true
        scrollView.backgroundColor = ColorRole.editorBackgroundNSColor

        let gutter = LineNumberGutterView(codeTextView: textView, scrollView: scrollView)
        scrollView.verticalRulerView = gutter
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = settings.editor.showLineNumbers

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.gutter = gutter

        let overlay = EditorOverlayView()
        overlay.textView = textView
        overlay.frame = textView.bounds
        overlay.autoresizingMask = [.width, .height]
        textView.addSubview(overlay, positioned: .above, relativeTo: nil)
        context.coordinator.overlay = overlay
        context.coordinator.attach(session: session, to: textView)
        context.coordinator.applyEditorSettings(to: textView, scrollView: scrollView)

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        scrollView.contentView.postsBoundsChangedNotifications = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        let desiredFont = Typography.editorFont(
            family: settings.typography.editorFontFamily,
            size: fontSize,
            ligatures: settings.typography.editorFontLigatures
        )
        if textView.font != desiredFont {
            textView.font = desiredFont
            context.coordinator.gutter?.invalidate()
        }
        textView.isEditable = !session.isReadOnly
        scrollView.rulersVisible = settings.editor.showLineNumbers
        context.coordinator.applyEditorSettings(to: textView, scrollView: scrollView)
        if let pending = session.pendingSelectionRange {
            textView.setSelectedRange(pending)
            session.selectionRange = pending
            session.pendingSelectionRange = nil
        }
        if context.coordinator.attachedSessionID != session.id {
            context.coordinator.attach(session: session, to: textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate, CodeTextViewCommandDelegate {
        var session: EditorDocumentSession
        var settings: AppSettingsStore
        let workspace: WorkspaceModel
        let onTextChanged: () -> Void
        weak var textView: CodeTextView?
        weak var scrollView: NSScrollView?
        weak var gutter: LineNumberGutterView?
        weak var overlay: EditorOverlayView?
        private(set) var attachedSessionID: UUID?

        private var pendingHighlightTask: Task<Void, Never>?
        private var viewportHighlightTask: Task<Void, Never>?
        private var lastAppliedViewportRange: NSRange?
        private var isApplyingHighlighting = false
        private var isApplyingCommand = false
        private var smartHomePressLine: Int?
        private var smartHomePressColumn: Int?

        init(
            session: EditorDocumentSession,
            settings: AppSettingsStore,
            workspace: WorkspaceModel,
            onTextChanged: @escaping () -> Void
        ) {
            self.session = session
            self.settings = settings
            self.workspace = workspace
            self.onTextChanged = onTextChanged
            super.init()
        }

        func applyEditorSettings(to textView: CodeTextView, scrollView: NSScrollView) {
            textView.highlightCurrentLine = settings.editor.highlightCurrentLine
            textView.configureWordWrap(enabled: settings.editor.wordWrap, in: scrollView)
            textView.backgroundColor = ColorRole.editorBackgroundNSColor
            textView.textColor = ColorRole.editorForegroundNSColor
            textView.insertionPointColor = ColorRole.editorForegroundNSColor
            textView.selectedTextAttributes = [.backgroundColor: ColorRole.editorSelectionNSColor]
            gutter?.isHidden = !settings.editor.showLineNumbers
            overlay?.showLongLineGuide = settings.editor.showLongLineGuide
            overlay?.guideColumn = settings.editor.longLineGuideColumn
            overlay?.showWhitespace = settings.editor.showWhitespace
            overlay?.showTrailingWhitespace = settings.editor.showTrailingWhitespace
            overlay?.findMatches = workspace.findReplace.isVisible
                ? workspace.findReplace.matches.map(\.range)
                : []
            if workspace.findReplace.isVisible,
               let activeIndex = workspace.findReplace.currentMatchIndex,
               workspace.findReplace.matches.indices.contains(activeIndex) {
                overlay?.activeFindMatch = workspace.findReplace.matches[activeIndex].range
            } else {
                overlay?.activeFindMatch = nil
            }
            overlay?.needsDisplay = true
        }

        func attach(session: EditorDocumentSession, to textView: CodeTextView) {
            if attachedSessionID == session.id { return }

            if let previous = self.textView, attachedSessionID != nil {
                self.session.selectionRange = previous.selectedRange()
                self.session.scrollOffset = scrollView?.contentView.bounds.origin ?? .zero
            }

            self.session = session
            attachedSessionID = session.id

            if let contentStorage = textView.textLayoutManager?.textContentManager as? NSTextContentStorage {
                contentStorage.textStorage = session.textStorage
            }
            session.textStorage.delegate = self

            gutter?.lineStartIndex = session.lineStartIndex
            textView.isEditable = !session.isReadOnly
            textView.setSelectedRange(session.selectionRange)
            if let scrollView {
                scrollView.contentView.scroll(to: session.scrollOffset)
            }

            if session.enablesSyntaxHighlighting, let highlighter = session.highlighter {
                let revision = session.bumpRevision()
                let text = session.textStorage.string
                Task { [weak self] in
                    let batch = await highlighter.load(text: text, revision: revision)
                    self?.apply(batch: batch)
                }
            }
        }

        @objc func boundsDidChange() {
            gutter?.invalidate()
