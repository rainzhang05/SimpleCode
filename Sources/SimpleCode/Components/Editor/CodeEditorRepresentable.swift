import AppKit
import SwiftUI

struct ProgrammaticUndoPayload: Equatable, Sendable {
    let edits: [TextEdit]
    let selection: NSRange
    let inverseSelection: NSRange

    var retainedUTF16Length: Int {
        edits.reduce(into: 0) { length, edit in
            length += edit.replacement.utf16.count
        }
    }
}

enum ProgrammaticLineIndexStrategy: Equatable, Sendable {
    case incremental
    case rebuildOnce
}

struct ProgrammaticEditPlan: Sendable {
    let forwardEdits: [TextEdit]
    let undoPayload: ProgrammaticUndoPayload
    let highlightEdit: TextEditDescriptor
    let lineIndexStrategy: ProgrammaticLineIndexStrategy

    static func prepare(
        edits: [TextEdit],
        documentLength: Int,
        undoSelection: NSRange,
        redoSelection: NSRange,
        replacedText: (NSRange) -> String
    ) -> ProgrammaticEditPlan? {
        guard !edits.isEmpty, documentLength >= 0 else { return nil }

        let sortedEdits = edits.sorted { lhs, rhs in
            if lhs.range.location == rhs.range.location {
                return lhs.range.length < rhs.range.length
            }
            return lhs.range.location < rhs.range.location
        }
        guard sortedEdits.allSatisfy({ edit in
            edit.range.location >= 0
                && edit.range.length >= 0
                && NSMaxRange(edit.range) <= documentLength
        }) else { return nil }
        for index in sortedEdits.indices.dropFirst() {
            let previous = sortedEdits[sortedEdits.index(before: index)]
            let current = sortedEdits[index]
            guard previous.range.location != current.range.location,
                  NSMaxRange(previous.range) <= current.range.location else { return nil }
        }

        var ascendingEdits: [TextEdit] = []
        ascendingEdits.reserveCapacity(sortedEdits.count)
        for edit in sortedEdits {
            if let previous = ascendingEdits.last,
               NSMaxRange(previous.range) == edit.range.location {
                ascendingEdits[ascendingEdits.count - 1] = TextEdit(
                    range: NSRange(
                        location: previous.range.location,
                        length: previous.range.length + edit.range.length
                    ),
                    replacement: previous.replacement + edit.replacement
                )
            } else {
                ascendingEdits.append(edit)
            }
        }

        var offsetDelta = 0
        var inverseEdits: [TextEdit] = []
        inverseEdits.reserveCapacity(ascendingEdits.count)
        for edit in ascendingEdits {
            let replacementLength = edit.replacement.utf16.count
            inverseEdits.append(TextEdit(
                range: NSRange(
                    location: edit.range.location + offsetDelta,
                    length: replacementLength
                ),
                replacement: replacedText(edit.range)
            ))
            offsetDelta += replacementLength - edit.range.length
        }

        let editStart = ascendingEdits[0].range.location
        let oldEditEnd = ascendingEdits.map { NSMaxRange($0.range) }.max() ?? editStart
        let forwardEdits = ascendingEdits.reversed()

        return ProgrammaticEditPlan(
            forwardEdits: Array(forwardEdits),
            undoPayload: ProgrammaticUndoPayload(
                edits: inverseEdits,
                selection: undoSelection,
                inverseSelection: redoSelection
            ),
            highlightEdit: TextEditDescriptor(
                startUTF16: editStart,
                oldEndUTF16: oldEditEnd,
                newEndUTF16: oldEditEnd + offsetDelta
            ),
            lineIndexStrategy: ascendingEdits.count == 1 ? .incremental : .rebuildOnce
        )
    }
}

struct CodeEditorRepresentable: NSViewRepresentable {
    var session: EditorDocumentSession
    var settings: AppSettingsSnapshot
    var workspace: WorkspaceModel
    var onTextChanged: () -> Void

    private var fontSize: CGFloat { CGFloat(settings.typography.editorFontSize) }

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
        context.coordinator.settings = settings
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

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.tearDown()
        scrollView.documentView = nil
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate, CodeTextViewCommandDelegate, EditorTextMutationApplying {
        var session: EditorDocumentSession
        var settings: AppSettingsSnapshot
        let workspace: WorkspaceModel
        let onTextChanged: () -> Void
        weak var textView: CodeTextView?
        weak var scrollView: NSScrollView?
        weak var gutter: LineNumberGutterView?
        weak var overlay: EditorOverlayView?
        private(set) var attachedSessionID: UUID?
        private var attachedSyntaxConfigurationRevision: Int?
        private var attachmentGeneration = 0
        private var lastParsedRevision: Int?
        private(set) var isTornDown = false

        private var pendingHighlightTask: Task<Void, Never>?
        private var viewportHighlightTask: Task<Void, Never>?
        private var initialRemainderTask: Task<Void, Never>?
        private var lastAppliedViewportRange: NSRange?
        private var lastBaseFont: NSFont?
        private var lastBaseForeground: StoredColorPair?
        private var lastAppliedAppearance: AppearanceSettings?
        private var isApplyingHighlighting = false
        private var isApplyingCommand = false
        private var smartHomePressLine: Int?
        private var smartHomePressColumn: Int?
        private var lastAppliedSettings = EditorAppliedSettings()
        private var lastWordWrapEnabled: Bool?

        init(
            session: EditorDocumentSession,
            settings: AppSettingsSnapshot,
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
            let previousAppearance = lastAppliedAppearance
            let appearanceChanged = previousAppearance != settings.appearance
            let syntaxColorsChanged = previousAppearance.map {
                $0.editorForeground != settings.appearance.editorForeground
                    || $0.syntaxPalette != settings.appearance.syntaxPalette
            } ?? false
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
            scrollView.backgroundColor = settings.appearance.editorBackground.colorRolePair.dynamic
            textView.backgroundColor = settings.appearance.editorBackground.colorRolePair.dynamic
            textView.textColor = settings.appearance.editorForeground.colorRolePair.dynamic
            textView.insertionPointColor = settings.appearance.editorForeground.colorRolePair.dynamic
            textView.selectedTextAttributes = [
                .backgroundColor: settings.appearance.editorSelection.colorRolePair.dynamic
            ]

            if lastWordWrapEnabled != snapshot.wordWrap {
                textView.configureWordWrap(enabled: snapshot.wordWrap, in: scrollView)
                lastWordWrapEnabled = snapshot.wordWrap
            }

            applyBaseTextAttributesIfNeeded(to: textView, force: false)
            if syntaxColorsChanged {
                session.refreshSyntaxAttributes()
            }

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

            if appearanceChanged {
                textView.needsDisplay = true
                gutter?.invalidate()
                overlay?.needsDisplay = true
            }

            lastAppliedSettings = snapshot
            lastAppliedAppearance = settings.appearance
        }

        func needsAttachment(for session: EditorDocumentSession) -> Bool {
            !isTornDown && (attachedSessionID != session.id
                || attachedSyntaxConfigurationRevision != session.syntaxConfigurationRevision
            )
        }

        func attach(session: EditorDocumentSession, to textView: CodeTextView) {
            guard !isTornDown, needsAttachment(for: session) else { return }

            pendingHighlightTask?.cancel()
            viewportHighlightTask?.cancel()
            initialRemainderTask?.cancel()
            pendingHighlightTask = nil
            viewportHighlightTask = nil
            initialRemainderTask = nil
            lastAppliedViewportRange = nil
            attachmentGeneration &+= 1

            if let previous = self.textView, attachedSessionID != nil, attachedSessionID != session.id {
                self.session.selectionRange = previous.selectedRange()
                self.session.scrollOffset = scrollView?.contentView.bounds.origin ?? .zero
                recordCurrentVisibleRange()
            }

            if attachedSessionID != session.id,
               self.session.textStorage.delegate === self {
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
            lastParsedRevision = session.hasAppliedSyntaxHighlighting ? session.revision : nil
            session.textStorage.delegate = self

            gutter?.lineStartIndex = session.lineStartIndex
            _ = gutter?.updateMetrics(font: textView.font, lineCount: session.lineStartIndex.lineCount)
            textView.configureLineNumberGutter(
                visible: settings.editor.showLineNumbers,
                width: gutter?.width ?? LineNumberGutterView.minimumWidth
            )
            textView.isEditable = !session.isReadOnly
            applyBaseTextAttributesIfNeeded(to: textView, force: true)
            textView.setSelectedRange(session.selectionRange)
            if let scrollView {
                scrollView.contentView.scroll(to: session.scrollOffset)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            recordCurrentVisibleRange()
            if session.enablesSyntaxHighlighting, let highlighter = session.highlighter, !session.hasAppliedSyntaxHighlighting {
                let revision = session.bumpRevision()
                let text = session.textStorage.string
                let sessionID = session.id
                let generation = attachmentGeneration
                let storage = session.textStorage
                pendingHighlightTask = Task { [weak self] in
                    let batch = await highlighter.load(text: text, revision: revision)
                    guard !Task.isCancelled,
                          let self,
                          self.recordParsedRevision(
                            revision,
                            expectedSessionID: sessionID,
                            expectedAttachmentGeneration: generation,
                            expectedTextStorage: storage
                          ) else { return }
                    self.apply(
                        batch: batch,
                        expectedSessionID: sessionID,
                        expectedAttachmentGeneration: generation,
                        expectedTextStorage: storage
                    )
                }
            } else {
                scheduleViewportHighlight()
                scheduleInitialRemainderIfNeeded()
            }
        }

        func tearDown() {
            guard !isTornDown else { return }
            isTornDown = true
            attachmentGeneration &+= 1
            pendingHighlightTask?.cancel()
            viewportHighlightTask?.cancel()
            initialRemainderTask?.cancel()
            pendingHighlightTask = nil
            viewportHighlightTask = nil
            initialRemainderTask = nil
            NotificationCenter.default.removeObserver(self)
            scrollView?.contentView.postsBoundsChangedNotifications = false

            if attachedSessionID == session.id {
                if let textView, textView.textStorage === session.textStorage {
                    session.selectionRange = textView.selectedRange()
                }
                session.scrollOffset = scrollView?.contentView.bounds.origin ?? session.scrollOffset
                recordCurrentVisibleRange()
            }

            if session.textStorage.delegate === self {
                session.textStorage.delegate = nil
            }
            if let textView {
                if textView.delegate === self {
                    textView.delegate = nil
                }
                if textView.commandDelegate === self {
                    textView.commandDelegate = nil
                }
                if let contentStorage = textView.textLayoutManager?.textContentManager as? NSTextContentStorage,
                   contentStorage.textStorage === session.textStorage {
                    contentStorage.textStorage = NSTextStorage()
                }
            }
            overlay?.textView = nil
            overlay?.removeFromSuperview()
            gutter?.removeFromSuperview()
            workspace.unregisterEditorMutationApplier(self, for: session)

            attachedSessionID = nil
            attachedSyntaxConfigurationRevision = nil
            lastParsedRevision = nil
            lastAppliedViewportRange = nil
            overlay = nil
            gutter = nil
            textView = nil
            scrollView = nil
        }

        @objc func boundsDidChange() {
            guard !isTornDown else { return }
            session.scrollOffset = scrollView?.contentView.bounds.origin ?? session.scrollOffset
            recordCurrentVisibleRange()
            gutter?.invalidate()
            overlay?.needsDisplay = true
            scheduleViewportHighlight()
        }

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard !isTornDown else { return }
            guard editedMask.contains(.editedCharacters) else { return }
            guard !isApplyingHighlighting else { return }
            guard !isApplyingCommand else { return }
            guard textStorage === session.textStorage else { return }

            applyBaseTextAttributes(to: textStorage, in: editedRange)

            let revision = session.bumpRevision()
            session.markDirty()
            onTextChanged()

            let insertedText = textStorage.attributedSubstring(from: editedRange).string
            session.lineStartIndex.applyEdit(
                editedRange: editedRange,
                changeInLength: delta,
                insertedText: insertedText,
                documentLength: textStorage.length,
                fullTextFallback: { textStorage.string }
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
            initialRemainderTask?.cancel()
            initialRemainderTask = nil
            let descriptor = TextEditDescriptor(
                startUTF16: editedRange.location,
                oldEndUTF16: editedRange.location + editedRange.length - delta,
                newEndUTF16: editedRange.location + editedRange.length
            )
            let sessionID = session.id
            let generation = attachmentGeneration
            pendingHighlightTask?.cancel()
            pendingHighlightTask = Task { [weak self] in
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
                      let request = self?.makeEditHighlightRequest(
                        revision: revision,
                        expectedSessionID: sessionID,
                        expectedAttachmentGeneration: generation,
                        expectedTextStorage: textStorage,
                        priorityOffset: descriptor.startUTF16
                      ) else { return }
                let result: (priority: HighlightBatch, remainder: HighlightBatch?)
                switch request.strategy {
                case .incremental:
                    result = await highlighter.applyEdit(
                        fullText: request.sourceText,
                        edit: descriptor,
                        revision: revision,
                        priorityUTF16Range: request.priorityRange
                    )
                case .full:
                    result = (
                        priority: await highlighter.load(text: request.sourceText, revision: revision),
                        remainder: nil
                    )
                }
                guard !Task.isCancelled,
                      let self,
                      self.recordParsedRevision(
                    revision,
                    expectedSessionID: sessionID,
                    expectedAttachmentGeneration: generation,
                    expectedTextStorage: textStorage
                ) else { return }
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
            guard !isTornDown else { return }
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
                guard !Task.isCancelled,
                      let request = self?.makeViewportHighlightRequest(
                        expectedSessionID: sessionID,
                        expectedAttachmentGeneration: generation,
                        expectedTextStorage: storage
                      ) else { return }
                let result = await request.highlighter.scheduleViewport(
                    fullText: request.sourceText,
                    revision: request.revision,
                    visibleUTF16Range: request.visibleRange
                )
                guard let self, !Task.isCancelled else { return }
                self.apply(
                    batch: result.priority,
                    expectedSessionID: sessionID,
                    expectedAttachmentGeneration: generation,
                    expectedTextStorage: storage
                )
                if let remainder = result.remainder {
                    self.apply(
                        batch: remainder,
                        expectedSessionID: sessionID,
                        expectedAttachmentGeneration: generation,
                        expectedTextStorage: storage
                    )
                }
                guard self.isCurrent(
                    sessionID: sessionID,
                    attachmentGeneration: generation,
                    textStorage: storage
                ), self.session.revision == request.revision else { return }
                self.lastAppliedViewportRange = request.visibleRange
            }
        }

        private func scheduleInitialRemainderIfNeeded() {
            initialRemainderTask?.cancel()
            guard !isTornDown, session.deferredInitialHighlightCursor != nil else {
                initialRemainderTask = nil
                return
            }
            let sessionID = session.id
            let generation = attachmentGeneration
            let storage = session.textStorage
            initialRemainderTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .milliseconds(8))
                } catch {
                    return
                }
                while !Task.isCancelled {
                    guard let request = self?.makeInitialRemainderRequest(
                        expectedSessionID: sessionID,
                        expectedAttachmentGeneration: generation,
                        expectedTextStorage: storage
                    ) else { return }
                    let page = await request.highlighter.continueInitial(
                        request.cursor,
                        pageSizeUTF16: InitialHighlightPaging.pageSizeUTF16
                    )
                    guard !Task.isCancelled,
                          let self,
                          self.isCurrent(
                            sessionID: sessionID,
                            attachmentGeneration: generation,
                            textStorage: storage
                          ),
                          self.session.revision == request.cursor.revision,
                          self.session.deferredInitialHighlightCursor == request.cursor else { return }
                    guard let page else {
                        self.session.advanceDeferredInitialHighlighting(from: request.cursor, to: nil)
                        return
                    }
                    guard page.batch.revision == request.cursor.revision,
                          self.apply(
                            batch: page.batch,
                            expectedSessionID: sessionID,
                            expectedAttachmentGeneration: generation,
                            expectedTextStorage: storage
                          ) else { return }
                    self.session.advanceDeferredInitialHighlighting(from: request.cursor, to: page.next)
                    guard page.next != nil else {
                        self.scheduleViewportHighlight()
                        return
                    }
                    do {
                        try await Task.sleep(for: .milliseconds(8))
                    } catch {
                        return
                    }
                }
            }
        }

        private func currentVisibleUTF16Range(fallbackAround offset: Int) -> NSRange {
            guard let textView else {
                return NSRange(location: max(0, offset), length: 0)
            }
            return EditorVisibleRange.visibleUTF16Range(in: textView)
                ?? NSRange(location: max(0, offset), length: 0)
        }

        private func recordCurrentVisibleRange() {
            guard let textView,
                  textView.textStorage === session.textStorage,
                  let visibleRange = EditorVisibleRange.visibleUTF16Range(in: textView) else { return }
            session.recordVisibleUTF16Range(visibleRange)
        }

        private func isCurrent(
            sessionID: UUID,
            attachmentGeneration: Int,
            textStorage: NSTextStorage
        ) -> Bool {
            !isTornDown
                && attachedSessionID == sessionID
                && self.attachmentGeneration == attachmentGeneration
                && session.id == sessionID
                && self.textView?.textStorage === textStorage
        }

        private func recordParsedRevision(
            _ revision: Int,
            expectedSessionID: UUID,
            expectedAttachmentGeneration: Int,
            expectedTextStorage: NSTextStorage
        ) -> Bool {
            guard isCurrent(
                sessionID: expectedSessionID,
                attachmentGeneration: expectedAttachmentGeneration,
                textStorage: expectedTextStorage
            ), session.revision == revision else { return false }
            lastParsedRevision = revision
            return true
        }

        private struct EditHighlightRequest {
            let sourceText: String
            let strategy: HighlightParseStrategy
            let priorityRange: NSRange
        }

        private func makeEditHighlightRequest(
            revision: Int,
            expectedSessionID: UUID,
            expectedAttachmentGeneration: Int,
            expectedTextStorage: NSTextStorage,
            priorityOffset: Int
        ) -> EditHighlightRequest? {
            guard isCurrent(
                sessionID: expectedSessionID,
                attachmentGeneration: expectedAttachmentGeneration,
                textStorage: expectedTextStorage
            ), session.revision == revision else { return nil }
            return EditHighlightRequest(
                sourceText: expectedTextStorage.string,
                strategy: session.deferredInitialHighlightCursor == nil
                    ? HighlightBatchApplicator.parseStrategy(
                        lastParsedRevision: lastParsedRevision,
                        requestedRevision: revision
                    )
                    : .full,
                priorityRange: currentVisibleUTF16Range(fallbackAround: priorityOffset)
            )
        }

        private struct ViewportHighlightRequest {
            let highlighter: any SyntaxHighlighter
            let sourceText: String
            let revision: Int
            let visibleRange: NSRange
        }

        private struct InitialRemainderRequest {
            let highlighter: any SyntaxHighlighter
            let cursor: InitialHighlightCursor
        }

        private func makeInitialRemainderRequest(
            expectedSessionID: UUID,
            expectedAttachmentGeneration: Int,
            expectedTextStorage: NSTextStorage
        ) -> InitialRemainderRequest? {
            guard isCurrent(
                sessionID: expectedSessionID,
                attachmentGeneration: expectedAttachmentGeneration,
                textStorage: expectedTextStorage
            ), session.enablesSyntaxHighlighting,
               let highlighter = session.highlighter,
               let cursor = session.deferredInitialHighlightCursor,
               cursor.revision == session.revision else { return nil }
            return InitialRemainderRequest(highlighter: highlighter, cursor: cursor)
        }

        private func makeViewportHighlightRequest(
            expectedSessionID: UUID,
            expectedAttachmentGeneration: Int,
            expectedTextStorage: NSTextStorage
        ) -> ViewportHighlightRequest? {
            guard isCurrent(
                sessionID: expectedSessionID,
                attachmentGeneration: expectedAttachmentGeneration,
                textStorage: expectedTextStorage
            ), session.enablesSyntaxHighlighting,
               let highlighter = session.highlighter,
               let textView,
               session.deferredInitialHighlightCursor == nil,
               lastParsedRevision == session.revision else { return nil }
            let visibleRange = currentVisibleUTF16Range(fallbackAround: 0)
            session.recordVisibleUTF16Range(visibleRange)
            guard lastAppliedViewportRange.map({ !NSEqualRanges($0, visibleRange) }) ?? true else {
                return nil
            }
            return ViewportHighlightRequest(
                highlighter: highlighter,
                sourceText: textView.string,
                revision: session.revision,
                visibleRange: visibleRange
            )
        }

        @discardableResult
        private func apply(
            batch: HighlightBatch,
            expectedSessionID: UUID,
            expectedAttachmentGeneration: Int,
            expectedTextStorage: NSTextStorage
        ) -> Bool {
            guard isCurrent(
                sessionID: expectedSessionID,
                attachmentGeneration: expectedAttachmentGeneration,
                textStorage: expectedTextStorage
            ) else { return false }
            guard HighlightBatchApplicator.shouldApply(batchRevision: batch.revision, currentRevision: session.revision) else { return false }
            let textStorage = expectedTextStorage
            session.mergeSyntaxTokens(batch.tokens, replacingCoveredRanges: batch.coveredRanges)
            isApplyingHighlighting = true
            HighlightBatchApplicator.apply(batch, to: textStorage)
            isApplyingHighlighting = false
            overlay?.needsDisplay = true
            textView?.needsDisplay = true
            return true
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
            resetSmartHomeIfMoved(from: line, column: selectedLocation - lineStart + 1)
            textView.needsDisplay = true
        }

        private func applyBaseTextAttributesIfNeeded(to textView: CodeTextView, force: Bool) {
            guard let font = textView.font else { return }
            let foreground = ColorRole.editorForegroundNSColor
            let paragraphStyle = NSParagraphStyle.default
            textView.typingAttributes = [
                .font: font,
                .foregroundColor: foreground,
                .paragraphStyle: paragraphStyle
            ]

            let foregroundChanged = lastBaseForeground != settings.appearance.editorForeground
            let needsBaseAttributes = force
                || lastBaseFont != font
                || foregroundChanged
            guard needsBaseAttributes else { return }

            lastBaseFont = font
            lastBaseForeground = settings.appearance.editorForeground

            guard let textStorage = textView.textStorage, textStorage.length > 0 else { return }
            isApplyingHighlighting = true
            textStorage.beginEditing()
            var baseAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]
            if !session.hasAppliedSyntaxHighlighting {
                baseAttributes[.foregroundColor] = foreground
            }
            textStorage.addAttributes(
                baseAttributes,
                range: NSRange(location: 0, length: textStorage.length)
            )
            textStorage.endEditing()
            isApplyingHighlighting = false
            textView.needsDisplay = true
        }

        private func applyBaseTextAttributes(to textStorage: NSTextStorage, in editedRange: NSRange) {
            guard let textView, let font = textView.font else { return }
            let documentRange = NSRange(location: 0, length: textStorage.length)
            let range = NSIntersectionRange(editedRange, documentRange)
            guard range.length > 0 else { return }

            isApplyingHighlighting = true
            textStorage.beginEditing()
            textStorage.addAttributes([
                .font: font,
                .foregroundColor: ColorRole.editorForegroundNSColor,
                .paragraphStyle: NSParagraphStyle.default
            ], range: range)
            textStorage.endEditing()
            isApplyingHighlighting = false
            textView.needsDisplay = true
        }

        // MARK: CodeTextViewCommandDelegate

        func codeTextViewHandleReturn(_ textView: CodeTextView) -> Bool {
            guard settings.editor.autoIndent else { return false }
            guard let result = workspace.editorReturnResult(for: session, selection: textView.selectedRange()) else { return false }
            applyCommand(result, in: textView)
            return true
        }

        func codeTextViewHandleTab(_ textView: CodeTextView, shift: Bool) -> Bool {
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

        func applyEditorMutation(_ result: EditorCommandResult, to targetSession: EditorDocumentSession) -> Bool {
            guard targetSession.id == session.id, let textView else { return false }
            applyCommand(result, in: textView)
            return true
        }

        private func applyCommand(_ result: EditorCommandResult, in textView: CodeTextView) {
            let selection = result.resultingSelections.first ?? textView.selectedRange()
            if !result.edits.isEmpty {
                applyTextEdits(result.edits, in: textView, resultingSelection: selection)
            } else {
                textView.setSelectedRange(selection)
                session.selectionRange = selection
            }
            textView.needsDisplay = true
            overlay?.needsDisplay = true
        }

        private func applyTextEdits(
            _ edits: [TextEdit],
            in textView: CodeTextView,
            resultingSelection: NSRange,
            inverseSelection: NSRange? = nil
        ) {
            guard let textStorage = textView.textStorage else { return }
            let originalSelection = inverseSelection ?? textView.selectedRange()
            guard let plan = ProgrammaticEditPlan.prepare(
                edits: edits,
                documentLength: textStorage.length,
                undoSelection: originalSelection,
                redoSelection: resultingSelection,
                replacedText: { textStorage.attributedSubstring(from: $0).string }
            ) else { return }

            isApplyingCommand = true
            textStorage.beginEditing()
            for edit in plan.forwardEdits {
                let replacementLength = edit.replacement.utf16.count
                let delta = replacementLength - edit.range.length
                textView.replaceCharacters(in: edit.range, with: edit.replacement)
                if plan.lineIndexStrategy == .incremental {
                    session.lineStartIndex.applyEdit(
                        editedRange: NSRange(location: edit.range.location, length: replacementLength),
                        changeInLength: delta,
                        insertedText: edit.replacement,
                        documentLength: textStorage.length,
                        fullTextFallback: { textStorage.string }
                    )
                }
            }
            textStorage.endEditing()
            if plan.lineIndexStrategy == .rebuildOnce {
                session.lineStartIndex.rebuild(from: textStorage.string)
            }
            isApplyingCommand = false

            textView.setSelectedRange(resultingSelection)
            session.selectionRange = resultingSelection

            registerUndo(
                in: textView,
                payload: plan.undoPayload,
                sessionID: session.id
            )

            recordProgrammaticSourceEdit(
                in: textView,
                descriptor: plan.highlightEdit
            )
        }

        private func registerUndo(
            in textView: CodeTextView,
            payload: ProgrammaticUndoPayload,
            sessionID: UUID
        ) {
            textView.undoManager?.registerUndo(withTarget: self) { [weak textView] coordinator in
                guard let textView else { return }
                coordinator.applyUndoPayload(
                    payload,
                    sessionID: sessionID,
                    in: textView
                )
            }
            textView.undoManager?.setActionName("Edit")
        }

        private func applyUndoPayload(
            _ payload: ProgrammaticUndoPayload,
            sessionID: UUID,
            in textView: CodeTextView
        ) {
            guard session.id == sessionID else { return }
            applyTextEdits(
                payload.edits,
                in: textView,
                resultingSelection: payload.selection,
                inverseSelection: payload.inverseSelection
            )
        }

        private func recordProgrammaticSourceEdit(
            in textView: CodeTextView,
            descriptor: TextEditDescriptor
        ) {
            let revision = session.bumpRevision()
            session.markDirty()
            onTextChanged()

            gutter?.lineStartIndex = session.lineStartIndex
            if gutter?.updateMetrics(font: textView.font, lineCount: session.lineStartIndex.lineCount) == true {
                textView.configureLineNumberGutter(
                    visible: settings.editor.showLineNumbers,
                    width: gutter?.width ?? LineNumberGutterView.minimumWidth
                )
            }
            gutter?.invalidate()

            guard session.enablesSyntaxHighlighting,
                  let highlighter = session.highlighter,
                  let storage = textView.textStorage else { return }
            initialRemainderTask?.cancel()
            initialRemainderTask = nil
            pendingHighlightTask?.cancel()
            let sessionID = session.id
            let generation = attachmentGeneration
            let priorityOffset = session.selectionRange.location
            pendingHighlightTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .milliseconds(40))
                } catch {
                    return
                }
                guard !Task.isCancelled,
                      let request = self?.makeEditHighlightRequest(
                        revision: revision,
                        expectedSessionID: sessionID,
                        expectedAttachmentGeneration: generation,
                        expectedTextStorage: storage,
                        priorityOffset: priorityOffset
                      ) else { return }
                let result: (priority: HighlightBatch, remainder: HighlightBatch?)
                switch request.strategy {
                case .incremental:
                    result = await highlighter.applyEdit(
                        fullText: request.sourceText,
                        edit: descriptor,
                        revision: revision,
                        priorityUTF16Range: request.priorityRange
                    )
                case .full:
                    result = (
                        priority: await highlighter.load(text: request.sourceText, revision: revision),
                        remainder: nil
                    )
                }
                guard !Task.isCancelled,
                      let self,
                      self.recordParsedRevision(
                    revision,
                    expectedSessionID: sessionID,
                    expectedAttachmentGeneration: generation,
                    expectedTextStorage: storage
                ) else { return }
                self.apply(
                    batch: result.priority,
                    expectedSessionID: sessionID,
                    expectedAttachmentGeneration: generation,
                    expectedTextStorage: storage
                )
                if let remainder = result.remainder {
                    self.apply(
                        batch: remainder,
                        expectedSessionID: sessionID,
                        expectedAttachmentGeneration: generation,
                        expectedTextStorage: storage
                    )
                }
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

private struct EditorAppliedSettings: Equatable {
    var highlightCurrentLine = true
    var showLongLineGuide = true
    var guideColumn = 100
    var showWhitespace = false
    var showTrailingWhitespace = false
    var wordWrap = false
    var showLineNumbers = true
    var findVisible = false
    var findMatches: [NSRange] = []
    var activeFindMatch: NSRange?

    var overlayDecorationSettings: OverlayDecorationSettings {
        OverlayDecorationSettings(
            showLongLineGuide: showLongLineGuide,
            guideColumn: guideColumn,
            showWhitespace: showWhitespace,
            showTrailingWhitespace: showTrailingWhitespace
        )
    }

    var findState: FindState {
        FindState(findVisible: findVisible, findMatches: findMatches, activeFindMatch: activeFindMatch)
    }

    struct OverlayDecorationSettings: Equatable {
        var showLongLineGuide: Bool
        var guideColumn: Int
        var showWhitespace: Bool
        var showTrailingWhitespace: Bool
    }

    struct FindState: Equatable {
        var findVisible: Bool
        var findMatches: [NSRange]
        var activeFindMatch: NSRange?
    }
}
