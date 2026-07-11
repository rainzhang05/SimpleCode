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
        textView.setAccessibilityIdentifier("editor.textView")
        textView.font = Typography.editorFont(
            family: settings.typography.editorFontFamily,
            size: fontSize,
            ligatures: settings.typography.editorFontLigatures
        )
        textView.isEditable = !session.isReadOnly

        let scrollView = NSScrollView()
        scrollView.setAccessibilityIdentifier("editor.scrollView")
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.drawsBackground = true
        scrollView.backgroundColor = ColorRole.editorBackgroundNSColor

        let gutter = LineNumberGutterView(codeTextView: textView)
        gutter.lineStartIndex = session.lineStartIndex
        _ = gutter.updateMetrics(font: textView.font, lineCount: session.lineStartIndex.lineCount)
        gutter.isHidden = !settings.editor.showLineNumbers
        textView.addSubview(gutter, positioned: .above, relativeTo: nil)
        textView.configureLineNumberGutter(visible: settings.editor.showLineNumbers, width: gutter.width)

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
        if context.coordinator.needsAttachment(for: session) {
            context.coordinator.attach(session: session, to: textView)
        }
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
        context.coordinator.applyEditorSettings(to: textView, scrollView: scrollView)
        if let pending = session.pendingSelectionRange {
            textView.setSelectedRange(pending)
            session.selectionRange = pending
            session.pendingSelectionRange = nil
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate, CodeTextViewCommandDelegate, EditorTextMutationApplying {
        var session: EditorDocumentSession
        var settings: AppSettingsStore
        let workspace: WorkspaceModel
        let onTextChanged: () -> Void
        weak var textView: CodeTextView?
        weak var scrollView: NSScrollView?
        weak var gutter: LineNumberGutterView?
        weak var overlay: EditorOverlayView?
        private(set) var attachedSessionID: UUID?
        private var attachedSyntaxConfigurationRevision: Int?
        private var attachmentGeneration = 0

        private var pendingHighlightTask: Task<Void, Never>?
        private var viewportHighlightTask: Task<Void, Never>?
        private var lastAppliedViewportRange: NSRange?
        private var lastBaseFont: NSFont?
        private var lastBaseForeground: StoredColorPair?
        private var lastBaseLineHeight: Double?
        private var isApplyingHighlighting = false
        private var isApplyingCommand = false
        private var smartHomePressLine: Int?
        private var smartHomePressColumn: Int?
        private var lastAppliedSettings = EditorAppliedSettings()
        private var lastWordWrapEnabled: Bool?

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
            let snapshot = EditorAppliedSettings(
                highlightCurrentLine: settings.editor.highlightCurrentLine,
                showLongLineGuide: settings.editor.showLongLineGuide,
                guideColumn: settings.editor.longLineGuideColumn,
                showWhitespace: settings.editor.showWhitespace,
                showTrailingWhitespace: settings.editor.showTrailingWhitespace,
                wordWrap: settings.editor.wordWrap,
                showLineNumbers: settings.editor.showLineNumbers,
                findVisible: workspace.findReplace.isVisible,
                findMatches: workspace.findReplace.isVisible
                    ? workspace.findReplace.matches.map(\.range)
                    : [],
                activeFindMatch: workspace.findReplace.isVisible
                    ? workspace.findReplace.currentMatchIndex.flatMap { index in
                        workspace.findReplace.matches.indices.contains(index)
                            ? workspace.findReplace.matches[index].range
                            : nil
                    }
                    : nil
            )

            textView.highlightCurrentLine = snapshot.highlightCurrentLine
            textView.backgroundColor = ColorRole.editorBackgroundNSColor
            textView.textColor = ColorRole.editorForegroundNSColor
            textView.insertionPointColor = ColorRole.editorForegroundNSColor
            textView.selectedTextAttributes = [.backgroundColor: ColorRole.editorSelectionNSColor]

            if lastWordWrapEnabled != snapshot.wordWrap {
                textView.configureWordWrap(enabled: snapshot.wordWrap, in: scrollView)
                lastWordWrapEnabled = snapshot.wordWrap
            }

            applyBaseTextAttributesIfNeeded(to: textView, force: false)

            let gutterMetricsChanged = gutter?.updateMetrics(
                font: textView.font,
                lineCount: session.lineStartIndex.lineCount
            ) ?? false
            if lastAppliedSettings.showLineNumbers != snapshot.showLineNumbers || gutterMetricsChanged {
                textView.configureLineNumberGutter(
                    visible: snapshot.showLineNumbers,
                    width: gutter?.width ?? LineNumberGutterView.minimumWidth
                )
                gutter?.isHidden = !snapshot.showLineNumbers
                gutter?.invalidate()
            }

            if lastAppliedSettings.overlayDecorationSettings != snapshot.overlayDecorationSettings {
                overlay?.showLongLineGuide = snapshot.showLongLineGuide
                overlay?.guideColumn = snapshot.guideColumn
                overlay?.showWhitespace = snapshot.showWhitespace
                overlay?.showTrailingWhitespace = snapshot.showTrailingWhitespace
                overlay?.needsDisplay = true
            }

            if lastAppliedSettings.findState != snapshot.findState {
                overlay?.findMatches = snapshot.findMatches
                overlay?.activeFindMatch = snapshot.activeFindMatch
                overlay?.needsDisplay = true
            }

            lastAppliedSettings = snapshot
        }

        func needsAttachment(for session: EditorDocumentSession) -> Bool {
            attachedSessionID != session.id
                || attachedSyntaxConfigurationRevision != session.syntaxConfigurationRevision
        }

        func attach(session: EditorDocumentSession, to textView: CodeTextView) {
            guard needsAttachment(for: session) else { return }

            pendingHighlightTask?.cancel()
            viewportHighlightTask?.cancel()
            pendingHighlightTask = nil
            viewportHighlightTask = nil
            lastAppliedViewportRange = nil
            attachmentGeneration &+= 1

            if let previous = self.textView, attachedSessionID != nil, attachedSessionID != session.id {
                self.session.selectionRange = previous.selectedRange()
                self.session.scrollOffset = scrollView?.contentView.bounds.origin ?? .zero
            }

            if attachedSessionID != session.id {
                self.session.textStorage.delegate = nil
            }

            self.session = session
            workspace.registerEditorMutationApplier(self, for: session)
            textView.attachUndoManager(session.undoManager)
            guard let contentStorage = textView.textLayoutManager?.textContentManager as? NSTextContentStorage else {
                assertionFailure("CodeTextView must use NSTextContentStorage")
                return
            }
            contentStorage.textStorage = session.textStorage
            attachedSessionID = session.id
            attachedSyntaxConfigurationRevision = session.syntaxConfigurationRevision
            session.textStorage.delegate = self

            gutter?.lineStartIndex = session.lineStartIndex
            _ = gutter?.updateMetrics(font: textView.font, lineCount: session.lineStartIndex.lineCount)
            textView.configureLineNumberGutter(
                visible: settings.editor.showLineNumbers,
                width: gutter?.width ?? LineNumberGutterView.minimumWidth
            )
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
            scheduleViewportHighlight()
        }

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) else { return }
            guard !isApplyingHighlighting else { return }
            guard !isApplyingCommand else { return }
            guard textStorage === session.textStorage else { return }

            applyBaseTextAttributes(to: textStorage, in: editedRange)

            let revision = session.bumpRevision()
            session.markDirty()
            onTextChanged()

            let insertedText = (textStorage.string as NSString).substring(with: editedRange)
            session.lineStartIndex.applyEdit(
                editedRange: editedRange,
                changeInLength: delta,
                insertedText: insertedText,
                fullText: textStorage.string
            )
            gutter?.lineStartIndex = session.lineStartIndex
            if let textView,
               gutter?.updateMetrics(font: textView.font, lineCount: session.lineStartIndex.lineCount) == true {
                textView.configureLineNumberGutter(
                    visible: settings.editor.showLineNumbers,
                    width: gutter?.width ?? LineNumberGutterView.minimumWidth
                )
            }
            gutter?.invalidate()
            overlay?.needsDisplay = true

            guard session.enablesSyntaxHighlighting, let highlighter = session.highlighter else { return }
            let descriptor = TextEditDescriptor(
                startUTF16: editedRange.location,
                oldEndUTF16: editedRange.location + editedRange.length - delta,
                newEndUTF16: editedRange.location + editedRange.length
            )
            let visibleRange = currentVisibleUTF16Range(fallbackAround: editedRange.location)
            let sessionID = session.id
            let generation = attachmentGeneration
            let sourceText = textStorage.string
            pendingHighlightTask?.cancel()
            pendingHighlightTask = Task { [weak self] in
                guard let self else { return }
                // A native text view can emit a character edit for every keypress.
                // Debounce before crossing the actor boundary so cancelled revisions
                // never accumulate as serialized parser work during a fast paste or
                // continuous typing burst.
                do {
                    try await Task.sleep(for: .milliseconds(40))
                } catch {
                    return
                }
                guard !Task.isCancelled,
                      self.session.id == sessionID,
                      self.attachmentGeneration == generation,
                      self.session.revision == revision,
                      self.textView?.textStorage === textStorage else { return }
                let result = await highlighter.applyEdit(
                    fullText: sourceText,
                    edit: descriptor,
                    revision: revision,
                    priorityUTF16Range: visibleRange
                )
                guard !Task.isCancelled else { return }
                self.apply(
                    batch: result.priority,
                    expectedSessionID: sessionID,
                    expectedAttachmentGeneration: generation,
                    expectedTextStorage: textStorage
                )
                if let remainder = result.remainder {
                    self.apply(
                        batch: remainder,
                        expectedSessionID: sessionID,
                        expectedAttachmentGeneration: generation,
                        expectedTextStorage: textStorage
                    )
                }
            }
        }

        private func scheduleViewportHighlight() {
            viewportHighlightTask?.cancel()
            let sessionID = session.id
            let generation = attachmentGeneration
            let storage = session.textStorage
            viewportHighlightTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self?.highlightVisibleViewport(
                    expectedSessionID: sessionID,
                    expectedAttachmentGeneration: generation,
                    expectedTextStorage: storage
                )
            }
        }

        private func highlightVisibleViewport(
            expectedSessionID: UUID,
            expectedAttachmentGeneration: Int,
            expectedTextStorage: NSTextStorage
        ) async {
            guard isCurrent(
                sessionID: expectedSessionID,
                attachmentGeneration: expectedAttachmentGeneration,
                textStorage: expectedTextStorage
            ) else { return }
            guard session.enablesSyntaxHighlighting, let highlighter = session.highlighter, let textView else { return }
            let visibleRange = currentVisibleUTF16Range(fallbackAround: 0)
            if let lastAppliedViewportRange, NSEqualRanges(lastAppliedViewportRange, visibleRange) { return }
            let text = textView.string
            let revision = session.revision
            let result = await highlighter.scheduleViewport(
                fullText: text,
                revision: revision,
                visibleUTF16Range: visibleRange
            )
            guard !Task.isCancelled else { return }
            apply(
                batch: result.priority,
                expectedSessionID: expectedSessionID,
                expectedAttachmentGeneration: expectedAttachmentGeneration,
                expectedTextStorage: expectedTextStorage
            )
            if let remainder = result.remainder {
                apply(
                    batch: remainder,
                    expectedSessionID: expectedSessionID,
                    expectedAttachmentGeneration: expectedAttachmentGeneration,
                    expectedTextStorage: expectedTextStorage
                )
            }
            lastAppliedViewportRange = visibleRange
        }

        private func currentVisibleUTF16Range(fallbackAround offset: Int) -> NSRange {
            guard let textView, let scrollView else {
                return NSRange(location: max(0, offset), length: 0)
            }
            return EditorVisibleRange.visibleUTF16Range(in: textView, scrollView: scrollView)
                ?? NSRange(location: max(0, offset), length: 0)
        }

        private func isCurrent(
            sessionID: UUID,
            attachmentGeneration: Int,
            textStorage: NSTextStorage
        ) -> Bool {
            attachedSessionID == sessionID
                && self.attachmentGeneration == attachmentGeneration
                && session.id == sessionID
                && self.textView?.textStorage === textStorage
        }

        private func apply(
            batch: HighlightBatch,
            expectedSessionID: UUID,
            expectedAttachmentGeneration: Int,
            expectedTextStorage: NSTextStorage
        ) {
            guard isCurrent(
                sessionID: expectedSessionID,
                attachmentGeneration: expectedAttachmentGeneration,
                textStorage: expectedTextStorage
            ) else { return }
            guard HighlightBatchApplicator.shouldApply(batchRevision: batch.revision, currentRevision: session.revision) else { return }
            let textStorage = expectedTextStorage
            session.mergeSyntaxTokens(batch.tokens, replacingCoveredRanges: batch.coveredRanges)
            let isDark = textView?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let appearance: EditorAppearance = isDark ? .dark : .light
            isApplyingHighlighting = true
            textStorage.beginEditing()
            for range in batch.coveredRanges where range.location >= 0 && NSMaxRange(range) <= textStorage.length {
                textStorage.addAttribute(.foregroundColor, value: ColorRole.editorForegroundNSColor, range: range)
            }
            for token in batch.tokens where token.range.location >= 0 && NSMaxRange(token.range) <= textStorage.length {
                textStorage.addAttribute(.foregroundColor, value: HighlightTheme.color(for: token.category, appearance: appearance), range: token.range)
            }
            textStorage.endEditing()
            isApplyingHighlighting = false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            gutter?.invalidate()
            overlay?.needsDisplay = true
            guard let textView else { return }
            let selectedLocation = textView.selectedRange().location
            let line = session.lineStartIndex.lineNumber(atUTF16Offset: selectedLocation)
            let lineStart = session.lineStartIndex.lineStartUTF16Offset(forLine: line)
            session.updateCursor(line: line, column: selectedLocation - lineStart + 1)
            session.selectionRange = textView.selectedRange()
            updateBracketHighlight(in: textView)
            resetSmartHomeIfMoved(from: line, column: selectedLocation - lineStart + 1)
        }

        // MARK: CodeTextViewCommandDelegate

        func codeTextViewHandleReturn(_ textView: CodeTextView) -> Bool {
            guard settings.editor.autoIndent else { return false }
            guard let result = workspace.editorReturnResult(for: session, selection: textView.selectedRange()) else { return false }
            applyCommand(result, in: textView)
            return true
        }

        func codeTextViewHandleTab(_ textView: CodeTextView, shift: Bool) -> Bool {
            guard settings.editor.autoIndent else { return false }
            guard let result = workspace.editorTabResult(for: session, selection: textView.selectedRange(), shift: shift) else { return false }
            applyCommand(result, in: textView)
            return true
        }

        func codeTextViewHandleDeleteBackward(_ textView: CodeTextView) -> Bool {
            guard settings.editor.smartBackspace else { return false }
            guard let result = workspace.editorBackspaceResult(for: session, selection: textView.selectedRange()) else { return false }
            applyCommand(result, in: textView)
            return true
        }

        func codeTextViewHandleMoveToBeginningOfLine(_ textView: CodeTextView, extendSelection: Bool) -> Bool {
            guard settings.editor.smartHome else { return false }
            let selection = textView.selectedRange()
            let line = session.lineStartIndex.lineNumber(atUTF16Offset: selection.location)
            let column = selection.location - session.lineStartIndex.lineStartUTF16Offset(forLine: line) + 1
            let isSecondPress = smartHomePressLine == line && smartHomePressColumn == column
            guard let result = workspace.editorHomeResult(
                for: session,
                selection: selection,
                isSecondPress: isSecondPress,
                extendSelection: extendSelection
            ) else { return false }
            applyCommand(result, in: textView)
            if let target = result.resultingSelections.first {
                let targetLine = session.lineStartIndex.lineNumber(atUTF16Offset: target.location)
                let targetColumn = target.location - session.lineStartIndex.lineStartUTF16Offset(forLine: targetLine) + 1
                smartHomePressLine = targetLine
                smartHomePressColumn = targetColumn
            }
            return true
        }

        func codeTextView(_ textView: CodeTextView, shouldInsertCharacter character: Character) -> Bool {
            guard settings.editor.autoClosingPairs else { return false }
            guard let result = workspace.editorPairInsertResult(
                for: session,
                character: character,
                selection: textView.selectedRange()
            ) else { return false }
            applyCommand(result, in: textView)
            return true
        }

        private func applyCommand(_ result: EditorCommandResult, in textView: CodeTextView) {
            if !result.edits.isEmpty {
                applyTextEdits(result.edits, in: textView)
            }
            if let selection = result.resultingSelections.first {
                textView.setSelectedRange(selection)
                session.selectionRange = selection
            }
            updateBracketHighlight(in: textView)
            textView.needsDisplay = true
            overlay?.needsDisplay = true
        }

        private func applyTextEdits(_ edits: [TextEdit], in textView: CodeTextView) {
            guard let textStorage = textView.textStorage else { return }
            let sortedEdits = edits.sorted { lhs, rhs in
                if lhs.range.location == rhs.range.location {
                    return lhs.range.length > rhs.range.length
                }
                return lhs.range.location > rhs.range.location
            }

            isApplyingCommand = true
            let undoManager = textView.undoManager
            undoManager?.beginUndoGrouping()
            textStorage.beginEditing()
            for edit in sortedEdits where edit.range.location >= 0 && NSMaxRange(edit.range) <= textStorage.length {
                textView.replaceCharacters(in: edit.range, with: edit.replacement)
            }
            textStorage.endEditing()
            undoManager?.endUndoGrouping()
            isApplyingCommand = false

            recordProgrammaticSourceEdit(in: textView)
        }

        private func recordProgrammaticSourceEdit(in textView: CodeTextView) {
            let revision = session.bumpRevision()
            session.markDirty()
            onTextChanged()

            session.lineStartIndex.rebuild(from: textView.string)
            gutter?.lineStartIndex = session.lineStartIndex
            gutter?.invalidate()

            guard session.enablesSyntaxHighlighting, let highlighter = session.highlighter else { return }
            pendingHighlightTask?.cancel()
            let text = textView.string
            pendingHighlightTask = Task { [weak self] in
                let batch = await highlighter.load(text: text, revision: revision)
                guard !Task.isCancelled else { return }
                self?.apply(batch: batch)
            }
        }

        private func updateBracketHighlight(in textView: CodeTextView) {
            let caret = textView.selectedRange().location
            let text = textView.string
            let controller = workspace.activeEditorCommandController(for: session)
            if let match = controller.matchingBracket(at: caret, in: text, syntaxContext: session.syntaxContext) {
                let open = min(caret, match)
                let close = max(caret, match)
                textView.bracketPair = (open, close)
            } else if caret > 0, let match = controller.matchingBracket(at: caret - 1, in: text, syntaxContext: session.syntaxContext) {
                let open = min(caret - 1, match)
                let close = max(caret - 1, match)
                textView.bracketPair = (open, close)
            } else {
                textView.bracketPair = nil
            }
        }

        private func resetSmartHomeIfMoved(from line: Int, column: Int) {
            if smartHomePressLine != line || smartHomePressColumn != column {
                smartHomePressLine = nil
                smartHomePressColumn = nil
            }
        }
    }
}
