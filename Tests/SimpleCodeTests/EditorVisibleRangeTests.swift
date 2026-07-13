import AppKit
import Foundation
import Testing
@testable import SimpleCode

struct EditorVisibleRangeTests {
    private actor SuspendedEditorHighlighter: SyntaxHighlighter {
        private var didStartLoad = false
        private var startWaiters: [CheckedContinuation<Void, Never>] = []
        private var loadContinuation: CheckedContinuation<Void, Never>?

        func waitUntilLoadStarts() async {
            if didStartLoad { return }
            await withCheckedContinuation { continuation in
                startWaiters.append(continuation)
            }
        }

        func resumeLoad() {
            loadContinuation?.resume()
            loadContinuation = nil
        }

        func load(text: String, revision: Int) async -> HighlightBatch {
            didStartLoad = true
            let waiters = startWaiters
            startWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                loadContinuation = continuation
            }
            return HighlightBatch(
                revision: revision,
                coveredRanges: [NSRange(location: 0, length: text.utf16.count)],
                tokens: text.isEmpty
                    ? []
                    : [SyntaxToken(range: NSRange(location: 0, length: min(3, text.utf16.count)), category: .keyword)]
            )
        }

        func applyEdit(
            fullText: String,
            edit: TextEditDescriptor,
            revision: Int,
            priorityUTF16Range: NSRange
        ) async -> (priority: HighlightBatch, remainder: HighlightBatch?) {
            (await load(text: fullText, revision: revision), nil)
        }

        func scheduleViewport(
            fullText: String,
            revision: Int,
            visibleUTF16Range: NSRange
        ) async -> (priority: HighlightBatch, remainder: HighlightBatch?) {
            (await load(text: fullText, revision: revision), nil)
        }
    }

    private actor RecordingEditorHighlighter: SyntaxHighlighter {
        private var loadTexts: [String] = []
        private var editTexts: [String] = []

        func snapshot() -> (loadTexts: [String], editTexts: [String]) {
            (loadTexts, editTexts)
        }

        func load(text: String, revision: Int) -> HighlightBatch {
            loadTexts.append(text)
            return HighlightBatch(
                revision: revision,
                coveredRanges: [NSRange(location: 0, length: text.utf16.count)],
                tokens: []
            )
        }

        func applyEdit(
            fullText: String,
            edit: TextEditDescriptor,
            revision: Int,
            priorityUTF16Range: NSRange
        ) -> (priority: HighlightBatch, remainder: HighlightBatch?) {
            editTexts.append(fullText)
            return (
                HighlightBatch(revision: revision, coveredRanges: [priorityUTF16Range], tokens: []),
                nil
            )
        }

        func scheduleViewport(
            fullText: String,
            revision: Int,
            visibleUTF16Range: NSRange
        ) -> (priority: HighlightBatch, remainder: HighlightBatch?) {
            (
                HighlightBatch(revision: revision, coveredRanges: [visibleUTF16Range], tokens: []),
                nil
            )
        }
    }

    private actor PagedRemainderHighlighter: SyntaxHighlighter {
        private let text: String
        private var continuationCount = 0

        init(text: String) {
            self.text = text
        }

        func pageCount() -> Int { continuationCount }

        func load(text: String, revision: Int) -> HighlightBatch {
            HighlightBatch(
                revision: revision,
                coveredRanges: [NSRange(location: 0, length: text.utf16.count)],
                tokens: []
            )
        }

        func continueInitial(
            _ cursor: InitialHighlightCursor,
            pageSizeUTF16: Int
        ) -> InitialHighlightPage? {
            guard let pageRange = InitialHighlightPaging.nextPageRange(
                in: text,
                cursor: cursor,
                pageSizeUTF16: pageSizeUTF16
            ) else { return nil }
            continuationCount += 1
            return InitialHighlightPage(
                batch: HighlightBatch(
                    revision: cursor.revision,
                    coveredRanges: [pageRange],
                    tokens: [SyntaxToken(
                        range: NSRange(location: pageRange.location, length: min(3, pageRange.length)),
                        category: .string
                    )]
                ),
                next: InitialHighlightPaging.advancing(cursor, past: pageRange)
            )
        }

        func applyEdit(
            fullText: String,
            edit: TextEditDescriptor,
            revision: Int,
            priorityUTF16Range: NSRange
        ) -> (priority: HighlightBatch, remainder: HighlightBatch?) {
            (load(text: fullText, revision: revision), nil)
        }

        func scheduleViewport(
            fullText: String,
            revision: Int,
            visibleUTF16Range: NSRange
        ) -> (priority: HighlightBatch, remainder: HighlightBatch?) {
            (
                HighlightBatch(revision: revision, coveredRanges: [visibleUTF16Range], tokens: []),
                nil
            )
        }
    }

    @MainActor
    private final class MutationApplierSpy: EditorTextMutationApplying {
        private(set) var applicationCount = 0

        func applyEditorMutation(_ result: EditorCommandResult, to session: EditorDocumentSession) -> Bool {
            applicationCount += 1
            return true
        }
    }

    @MainActor
    @Test func attachingPreparedSyntaxDoesNotResetTokenForeground() throws {
        let suiteName = "SimpleCode.PreparedSyntax.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory.appending(path: "PreparedSyntax-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = AppSettingsStore(defaults: defaults)
        let workspace = WorkspaceModel(
            id: UUID(),
            rootURL: root,
            appSettings: settings,
            workspaceStateStore: WorkspaceStateStore(defaults: defaults, storageKey: "prepared-syntax")
        )
        defer { workspace.tearDown() }

        let session = EditorDocumentSession(displayName: "Prepared.swift")
        session.textStorage.setAttributedString(NSAttributedString(string: "let prepared = true"))
        session.applyInitialHighlighting(HighlightBatch(
            revision: 0,
            coveredRanges: [NSRange(location: 0, length: session.textStorage.length)],
            tokens: [SyntaxToken(range: NSRange(location: 0, length: 3), category: .keyword)]
        ))
        let expected = try #require(session.textStorage.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor)

        let textView = CodeTextView()
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        let coordinator = CodeEditorRepresentable.Coordinator(
            session: session,
            settings: settings.snapshot,
            workspace: workspace,
            onTextChanged: {}
        )
        coordinator.textView = textView
        coordinator.scrollView = scrollView
        coordinator.attach(session: session, to: textView)

        let actual = try #require(session.textStorage.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor)
        let aqua = try #require(NSAppearance(named: .aqua))
        var expectedRGB: NSColor?
        var actualRGB: NSColor?
        aqua.performAsCurrentDrawingAppearance {
            expectedRGB = expected.usingColorSpace(.sRGB)
            actualRGB = actual.usingColorSpace(.sRGB)
        }
        let resolvedExpected = try #require(expectedRGB)
        let resolvedActual = try #require(actualRGB)
        #expect(abs(resolvedActual.redComponent - resolvedExpected.redComponent) < 0.000_1)
        #expect(abs(resolvedActual.greenComponent - resolvedExpected.greenComponent) < 0.000_1)
        #expect(abs(resolvedActual.blueComponent - resolvedExpected.blueComponent) < 0.000_1)
    }

    @MainActor
    @Test func coordinatorTeardownDetachesEditorGraphAndDelegates() throws {
        let suiteName = "SimpleCode.EditorTeardown.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory.appending(path: "EditorTeardown-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = AppSettingsStore(defaults: defaults)
        let workspace = WorkspaceModel(
            id: UUID(),
            rootURL: root,
            appSettings: settings,
            workspaceStateStore: WorkspaceStateStore(defaults: defaults, storageKey: "editor-teardown")
        )
        defer { workspace.tearDown() }
        let session = EditorDocumentSession(displayName: "Teardown.swift")
        session.textStorage.setAttributedString(NSAttributedString(string: "let teardown = true"))
        session.enablesSyntaxHighlighting = false

        let textView = CodeTextView()
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        let coordinator = CodeEditorRepresentable.Coordinator(
            session: session,
            settings: settings.snapshot,
            workspace: workspace,
            onTextChanged: {}
        )
        coordinator.textView = textView
        coordinator.scrollView = scrollView
        textView.delegate = coordinator
        textView.commandDelegate = coordinator
        coordinator.attach(session: session, to: textView)

        CodeEditorRepresentable.dismantleNSView(scrollView, coordinator: coordinator)
        CodeEditorRepresentable.dismantleNSView(scrollView, coordinator: coordinator)

        #expect(coordinator.isTornDown)
        #expect(scrollView.documentView == nil)
        #expect(textView.delegate == nil)
        #expect(textView.commandDelegate == nil)
        #expect(session.textStorage.delegate == nil)
        let contentStorage = try #require(textView.textLayoutManager?.textContentManager as? NSTextContentStorage)
        #expect(contentStorage.textStorage !== session.textStorage)
    }

    @MainActor
    @Test func teardownDuringSuspendedHighlightReleasesCoordinatorAndRejectsBatch() async throws {
        let suiteName = "SimpleCode.EditorTeardownHighlight.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory.appending(path: "EditorTeardownHighlight-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = AppSettingsStore(defaults: defaults)
        let workspace = WorkspaceModel(
            id: UUID(),
            rootURL: root,
            appSettings: settings,
            workspaceStateStore: WorkspaceStateStore(defaults: defaults, storageKey: "editor-teardown-highlight")
        )
        defer { workspace.tearDown() }
        let highlighter = SuspendedEditorHighlighter()
        let session = EditorDocumentSession(displayName: "Suspended.swift")
        session.textStorage.setAttributedString(NSAttributedString(string: "let suspended = true"))
        session.highlighter = highlighter

        let textView = CodeTextView()
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        var coordinator: CodeEditorRepresentable.Coordinator? = CodeEditorRepresentable.Coordinator(
            session: session,
            settings: settings.snapshot,
            workspace: workspace,
            onTextChanged: {}
        )
        weak let releasedCoordinator = coordinator
        coordinator?.textView = textView
        coordinator?.scrollView = scrollView
        coordinator?.attach(session: session, to: textView)

        await highlighter.waitUntilLoadStarts()
        do {
            let activeCoordinator = try #require(coordinator)
            CodeEditorRepresentable.dismantleNSView(scrollView, coordinator: activeCoordinator)
        }
        coordinator = nil
        await Task.yield()

        #expect(releasedCoordinator == nil)
        await highlighter.resumeLoad()
        await Task.yield()
        #expect(!session.hasAppliedSyntaxHighlighting)
    }

    @MainActor
    @Test func skippedTypingRevisionUsesOneFullParseOfLatestText() async throws {
        let suiteName = "SimpleCode.EditorRevisionGap.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory.appending(path: "EditorRevisionGap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = AppSettingsStore(defaults: defaults)
        let workspace = WorkspaceModel(
            id: UUID(),
            rootURL: root,
            appSettings: settings,
            workspaceStateStore: WorkspaceStateStore(defaults: defaults, storageKey: "editor-revision-gap")
        )
        defer { workspace.tearDown() }
        let highlighter = RecordingEditorHighlighter()
        let session = EditorDocumentSession(displayName: "Gap.swift")
        session.textStorage.setAttributedString(NSAttributedString(string: "let gap"))
        session.highlighter = highlighter
        session.applyInitialHighlighting(HighlightBatch(
            revision: 0,
            coveredRanges: [NSRange(location: 0, length: session.textStorage.length)],
            tokens: [SyntaxToken(range: NSRange(location: 0, length: 3), category: .keyword)]
        ))

        let textView = CodeTextView()
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        let coordinator = CodeEditorRepresentable.Coordinator(
            session: session,
            settings: settings.snapshot,
            workspace: workspace,
            onTextChanged: {}
        )
        coordinator.textView = textView
        coordinator.scrollView = scrollView
        coordinator.attach(session: session, to: textView)

        session.textStorage.append(NSAttributedString(string: "1"))
        session.textStorage.append(NSAttributedString(string: "2"))
        try await Task.sleep(for: .milliseconds(120))

        let calls = await highlighter.snapshot()
        #expect(calls.loadTexts == ["let gap12"])
        #expect(calls.editTexts.isEmpty)
        coordinator.tearDown()
    }

    @MainActor
    @Test func nativeAttachmentCompletesDeferredInitialHighlightPages() async throws {
        let suiteName = "SimpleCode.EditorInitialPages.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory.appending(path: "EditorInitialPages-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = AppSettingsStore(defaults: defaults)
        let workspace = WorkspaceModel(
            id: UUID(),
            rootURL: root,
            appSettings: settings,
            workspaceStateStore: WorkspaceStateStore(defaults: defaults, storageKey: "editor-initial-pages")
        )
        defer { workspace.tearDown() }
        let text = String(repeating: "let paged = true\n", count: 8_000)
        let highlighter = PagedRemainderHighlighter(text: text)
        let session = EditorDocumentSession(displayName: "Paged.swift")
        session.textStorage.setAttributedString(NSAttributedString(string: text))
        session.highlighter = highlighter
        let priorityRange = InitialHighlightPaging.priorityRange(in: text, aroundUTF16Offset: 0)
        session.applyInitialHighlighting(HighlightBatch(
            revision: 0,
            coveredRanges: [priorityRange],
            tokens: [SyntaxToken(range: NSRange(location: 0, length: 3), category: .keyword)]
        ))
        let remaining = InitialHighlightPaging.remainingRanges(
            documentLength: text.utf16.count,
            excluding: priorityRange
        )
        let cursor = InitialHighlightCursor(generation: 1, revision: 0, remainingRanges: remaining)
        session.deferInitialHighlighting(cursor)

        let textView = CodeTextView()
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        let coordinator = CodeEditorRepresentable.Coordinator(
            session: session,
            settings: settings.snapshot,
            workspace: workspace,
            onTextChanged: {}
        )
        coordinator.textView = textView
        coordinator.scrollView = scrollView
        coordinator.attach(session: session, to: textView)

        for _ in 0..<100 where session.deferredInitialHighlightCursor != nil {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(session.deferredInitialHighlightCursor == nil)
        #expect(await highlighter.pageCount() > 0)
        let firstRemainderOffset = try #require(remaining.first?.location)
        let remainderColor = session.textStorage.attribute(
            .foregroundColor,
            at: firstRemainderOffset,
            effectiveRange: nil
        ) as? NSColor
        #expect(remainderColor != nil)
        #expect(remainderColor != ColorRole.editorForegroundNSColor)
        coordinator.tearDown()
    }

    @MainActor
    @Test func unregisteringOldMutationApplierPreservesNewRegistration() throws {
        let suiteName = "SimpleCode.EditorMutationRegistration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory.appending(path: "EditorMutationRegistration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = AppSettingsStore(defaults: defaults)
        let workspace = WorkspaceModel(
            id: UUID(),
            rootURL: root,
            appSettings: settings,
            workspaceStateStore: WorkspaceStateStore(defaults: defaults, storageKey: "editor-mutation-registration")
        )
        defer { workspace.tearDown() }
        let session = EditorDocumentSession(displayName: "Registration.swift")
        let oldApplier = MutationApplierSpy()
        let currentApplier = MutationApplierSpy()

        workspace.registerEditorMutationApplier(oldApplier, for: session)
        workspace.registerEditorMutationApplier(currentApplier, for: session)
        workspace.unregisterEditorMutationApplier(oldApplier, for: session)
        workspace.applyEditorCommand(
            EditorCommandResult(edits: [], resultingSelections: [NSRange(location: 0, length: 0)]),
            session: session
        )

        #expect(oldApplier.applicationCount == 0)
        #expect(currentApplier.applicationCount == 1)
    }

    @MainActor
    @Test func currentLineHighlightSurvivesBaseBackgroundPaint() throws {
        let originalSnapshot = SettingsColorResolver.snapshot
        var testAppearance = originalSnapshot.appearance
        let white = StoredColor(red: 1, green: 1, blue: 1)
        let marker = StoredColor(red: 0.12, green: 0.83, blue: 0.29)
        testAppearance.editorBackground = StoredColorPair(light: white, dark: white)
        testAppearance.editorCurrentLine = StoredColorPair(light: marker, dark: marker)
        SettingsColorResolver.updateSnapshot(AppSettingsSnapshot(
            appearance: testAppearance,
            typography: originalSnapshot.typography,
            editor: originalSnapshot.editor,
            files: originalSnapshot.files
        ))
        defer { SettingsColorResolver.updateSnapshot(originalSnapshot) }

        let textView = CodeTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 240, height: 90)
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.string = "first line\nsecond line"
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.layoutSubtreeIfNeeded()
        textView.textLayoutManager?.textViewportLayoutController.layoutViewport()

        let bitmap = try #require(textView.bitmapImageRepForCachingDisplay(in: textView.bounds))
        textView.cacheDisplay(in: textView.bounds, to: bitmap)

        var foundMarker = false
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 3) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if abs(color.redComponent - marker.red) < 0.04,
                   abs(color.greenComponent - marker.green) < 0.04,
                   abs(color.blueComponent - marker.blue) < 0.04 {
                    foundMarker = true
                    break
                }
            }
            if foundMarker { break }
        }

        #expect(foundMarker)
    }

    @MainActor
    @Test func sharedTextGeometryAccountsForInsetsPaddingAndScrollCoordinates() throws {
        let textView = CodeTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        textView.textContainerInset = NSSize(width: 47, height: 19)
        textView.textContainer?.lineFragmentPadding = 7

        let origin = textView.textContainerOrigin
        let layoutFrame = NSRect(x: 4, y: 11, width: 120, height: 22)
        let viewFrame = EditorTextGeometry.viewFrame(for: layoutFrame, in: textView)
        #expect(viewFrame.origin.x == layoutFrame.origin.x + origin.x)
        #expect(viewFrame.origin.y == layoutFrame.origin.y + origin.y)

        let lookupX = EditorTextGeometry.textLookupX(in: textView)
        #expect(lookupX == origin.x + 7)

        let scrolledViewPoint = NSPoint(x: lookupX, y: 143)
        let layoutPoint = EditorTextGeometry.layoutPoint(forViewPoint: scrolledViewPoint, in: textView)
        #expect(layoutPoint.x == 7)
        #expect(layoutPoint.y == scrolledViewPoint.y - origin.y)
    }

    @MainActor
    @Test func wrappedParagraphUsesItsFirstVisualLineForGutterAlignment() throws {
        let (textView, fragment) = try makeLaidOutTextView(
            text: String(repeating: "wrapped words need several visual rows ", count: 8),
            wordWrap: true,
            width: 150
        )
        #expect(fragment.textLineFragments.count > 1)

        let firstLineFrame = try #require(
            EditorTextGeometry.firstLineViewFrame(in: fragment, textView: textView)
        )
        let firstLineBounds = try #require(fragment.textLineFragments.first).typographicBounds
        let expectedLayoutFrame = firstLineBounds.offsetBy(
            dx: fragment.layoutFragmentFrame.minX,
            dy: fragment.layoutFragmentFrame.minY
        )
        let expectedViewFrame = EditorTextGeometry.viewFrame(for: expectedLayoutFrame, in: textView)

        #expect(abs(firstLineFrame.minY - expectedViewFrame.minY) < 0.001)
        #expect(abs(firstLineFrame.midY - expectedViewFrame.midY) < 0.001)
        #expect(firstLineFrame.maxY < EditorTextGeometry.viewFrame(
            for: fragment.layoutFragmentFrame,
            in: textView
        ).maxY)
    }

    @MainActor
    @Test func unwrappedParagraphKeepsGutterOnItsSingleVisualLine() throws {
        let (textView, fragment) = try makeLaidOutTextView(
            text: String(repeating: "one horizontal line ", count: 12),
            wordWrap: false,
            width: 150
        )
        #expect(fragment.textLineFragments.count == 1)

        let firstLineFrame = try #require(
            EditorTextGeometry.firstLineViewFrame(in: fragment, textView: textView)
        )
        let firstLineBounds = try #require(fragment.textLineFragments.first).typographicBounds
        let expectedLayoutFrame = firstLineBounds.offsetBy(
            dx: fragment.layoutFragmentFrame.minX,
            dy: fragment.layoutFragmentFrame.minY
        )
        let expectedViewFrame = EditorTextGeometry.viewFrame(for: expectedLayoutFrame, in: textView)

        #expect(abs(firstLineFrame.midY - expectedViewFrame.midY) < 0.001)
    }

    @MainActor
    @Test func codeTextViewBuildsOneTextKit2Graph() throws {
        let textView = CodeTextView()

        #expect(textView.isUsingTextKit2)
        let layoutManager = try #require(textView.textLayoutManager)
        let contentStorage = try #require(layoutManager.textContentManager as? NSTextContentStorage)
        #expect(textView.textContentStorage === contentStorage)
        #expect(contentStorage.textStorage === textView.textStorage)
        #expect(layoutManager.textContainer === textView.textContainer)
    }

    @MainActor
    private func makeLaidOutTextView(
        text: String,
        wordWrap: Bool,
        width: CGFloat
    ) throws -> (CodeTextView, NSTextLayoutFragment) {
        let textView = CodeTextView()
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.string = text
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: 180))
        scrollView.documentView = textView
        textView.frame = NSRect(x: 0, y: 0, width: width, height: 600)
        textView.configureWordWrap(enabled: wordWrap, in: scrollView)
        scrollView.layoutSubtreeIfNeeded()
        let layoutManager = try #require(textView.textLayoutManager)
        let contentManager = try #require(layoutManager.textContentManager)
        layoutManager.ensureLayout(for: contentManager.documentRange)
        let fragment = try #require(layoutManager.textLayoutFragment(for: NSPoint(
            x: textView.textContainer?.lineFragmentPadding ?? 0,
            y: 0
        )))
        return (textView, fragment)
    }

    @MainActor
    @Test func lineNumberGutterIsANoninteractiveTextKit2Subview() {
        let textView = CodeTextView()
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        let gutter = LineNumberGutterView(codeTextView: textView)
        let asView: NSView = gutter

        textView.addSubview(gutter)

        #expect(gutter.superview === textView)
        #expect(gutter.hitTest(.zero) == nil)
        #expect(!(asView is NSRulerView))
    }

    @MainActor
    @Test func coordinatorAttachesEachSessionStorageToTheTextKit2ContentStorage() throws {
        let suiteName = "SimpleCode.EditorVisibleRangeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory.appending(path: "SimpleCodeEditorStorage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = AppSettingsStore(defaults: defaults)
        let workspace = WorkspaceModel(
            id: UUID(),
            rootURL: root,
            appSettings: settings,
            workspaceStateStore: WorkspaceStateStore(defaults: defaults, storageKey: "editor-storage.\(UUID().uuidString)")
        )
        defer { workspace.tearDown() }

        let firstSession = EditorDocumentSession(displayName: "First.swift")
        firstSession.textStorage.setAttributedString(NSAttributedString(string: "let first = 1"))
        firstSession.enablesSyntaxHighlighting = false

        let secondSession = EditorDocumentSession(displayName: "Second.txt")
        secondSession.textStorage.setAttributedString(NSAttributedString(string: "plain second document"))
        secondSession.selectionRange = NSRange(location: 3, length: 0)
        secondSession.enablesSyntaxHighlighting = false

        let textView = CodeTextView()
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let scrollView = NSScrollView()
        scrollView.documentView = textView

        let coordinator = CodeEditorRepresentable.Coordinator(
            session: firstSession,
            settings: settings.snapshot,
            workspace: workspace,
            onTextChanged: {}
        )
        coordinator.textView = textView
        coordinator.scrollView = scrollView
        coordinator.attach(session: firstSession, to: textView)

        textView.setSelectedRange(NSRange(location: 2, length: 0))
        coordinator.attach(session: secondSession, to: textView)

        let layoutManager = try #require(textView.textLayoutManager)
        let contentStorage = try #require(layoutManager.textContentManager as? NSTextContentStorage)
        #expect(contentStorage.textStorage === secondSession.textStorage)
        #expect(textView.textStorage === secondSession.textStorage)
        #expect(firstSession.selectionRange == NSRange(location: 2, length: 0))
        #expect(textView.selectedRange() == secondSession.selectionRange)
        #expect(textView.allowsUndo)
        #expect(secondSession.textStorage.attribute(.font, at: 0, effectiveRange: nil) is NSFont)
    }

    @MainActor
    @Test func coordinatorPersistsScrollOffsetAndVisibleRangeWhenBoundsChange() throws {
        let suiteName = "SimpleCode.EditorScrollState.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory.appending(path: "EditorScrollState-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = AppSettingsStore(defaults: defaults)
        let workspace = WorkspaceModel(
            id: UUID(),
            rootURL: root,
            appSettings: settings,
            workspaceStateStore: WorkspaceStateStore(defaults: defaults, storageKey: "editor-scroll-state")
        )
        defer { workspace.tearDown() }

        let session = EditorDocumentSession(displayName: "Scrolled.swift")
        session.textStorage.setAttributedString(NSAttributedString(
            string: String(repeating: "let visible = true\n", count: 500)
        ))
        session.enablesSyntaxHighlighting = false
        let textView = CodeTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 8_000))
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        scrollView.documentView = textView
        let coordinator = CodeEditorRepresentable.Coordinator(
            session: session,
            settings: settings.snapshot,
            workspace: workspace,
            onTextChanged: {}
        )
        coordinator.textView = textView
        coordinator.scrollView = scrollView
        coordinator.attach(session: session, to: textView)

        scrollView.contentView.scroll(to: CGPoint(x: 0, y: 900))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        coordinator.boundsDidChange()

        #expect(session.scrollOffset.y == 900)
        #expect(session.lastVisibleUTF16Range?.length ?? 0 > 0)
        coordinator.tearDown()
    }

    @MainActor
    @Test func coordinatorStylesContentThatArrivesAfterAttachment() throws {
        let suiteName = "SimpleCode.EditorVisibleRangeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory.appending(path: "SimpleCodeDelayedEditorStorage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = AppSettingsStore(defaults: defaults)
        let workspace = WorkspaceModel(
            id: UUID(),
            rootURL: root,
            appSettings: settings,
            workspaceStateStore: WorkspaceStateStore(defaults: defaults, storageKey: "delayed-editor-storage.\(UUID().uuidString)")
        )
        defer { workspace.tearDown() }

        let session = EditorDocumentSession(displayName: "Delayed.swift")
        session.enablesSyntaxHighlighting = false
        let textView = CodeTextView()
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        let coordinator = CodeEditorRepresentable.Coordinator(
            session: session,
            settings: settings.snapshot,
            workspace: workspace,
            onTextChanged: {}
        )
        coordinator.textView = textView
        coordinator.scrollView = scrollView
        coordinator.attach(session: session, to: textView)

        session.textStorage.setAttributedString(NSAttributedString(string: "let renderedAfterAttachment = true"))

        let font = try #require(session.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        _ = try #require(session.textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        #expect(font == textView.font)
    }

    @Test func unionMergesOverlappingRanges() {
        let lhs = NSRange(location: 10, length: 20)
        let rhs = NSRange(location: 25, length: 10)
        let merged = EditorVisibleRange.union(lhs, rhs, documentLength: 100)
        #expect(merged.location == 10)
        #expect(merged.length == 25)
    }

    @Test func unionClampsToDocumentLength() {
        let lhs = NSRange(location: 90, length: 20)
        let rhs = NSRange(location: 95, length: 20)
        let merged = EditorVisibleRange.union(lhs, rhs, documentLength: 100)
        #expect(merged.location == 90)
        #expect(merged.length == 10)
    }

    @Test func unionHandlesDisjointRanges() {
        let lhs = NSRange(location: 0, length: 5)
        let rhs = NSRange(location: 20, length: 5)
        let merged = EditorVisibleRange.union(lhs, rhs, documentLength: 100)
        #expect(merged.location == 0)
        #expect(merged.length == 25)
    }

    @MainActor
    @Test func selectedReturnFallsBackToTheNativeTextViewTransaction() throws {
        let suiteName = "SimpleCode.EditorVisibleRangeTests.Return.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory.appending(path: "SimpleCodeEditorReturn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = WorkspaceModel(
            id: UUID(),
            rootURL: root,
            appSettings: AppSettingsStore(defaults: defaults),
            workspaceStateStore: WorkspaceStateStore(defaults: defaults, storageKey: "editor-return.\(UUID().uuidString)")
        )
        let session = EditorDocumentSession(displayName: "Return.swift")
        session.textStorage.setAttributedString(NSAttributedString(string: "abc"))

        #expect(workspace.editorReturnResult(for: session, selection: NSRange(location: 1, length: 1)) == nil)
    }

    @Test func programmaticUndoPayloadRetainsOnlyTheReplacedSubstring() throws {
        let documentLength = 1_000_000
        let editRange = NSRange(location: documentLength / 2, length: 1)
        var requestedSubstrings: [NSRange] = []

        let plan = try #require(ProgrammaticEditPlan.prepare(
            edits: [TextEdit(range: editRange, replacement: "expanded")],
            documentLength: documentLength,
            undoSelection: NSRange(location: editRange.location, length: 0),
            redoSelection: NSRange(location: editRange.location + "expanded".utf16.count, length: 0),
            replacedText: { range in
                requestedSubstrings.append(range)
                return "x"
            }
        ))

        #expect(requestedSubstrings == [editRange])
        #expect(plan.undoPayload.retainedUTF16Length == 1)
        #expect(plan.undoPayload.edits == [
            TextEdit(
                range: NSRange(location: editRange.location, length: "expanded".utf16.count),
                replacement: "x"
            )
        ])
        #expect(plan.undoPayload.selection == NSRange(location: editRange.location, length: 0))
        #expect(plan.undoPayload.inverseSelection == NSRange(
            location: editRange.location + "expanded".utf16.count,
            length: 0
        ))
    }

    @Test func multipleProgrammaticEditsChooseOneBatchedLineIndexRebuild() throws {
        let plan = try #require(ProgrammaticEditPlan.prepare(
            edits: [
                TextEdit(range: NSRange(location: 0, length: 0), replacement: "    "),
                TextEdit(range: NSRange(location: 2, length: 0), replacement: "    ")
            ],
            documentLength: 3,
            undoSelection: NSRange(location: 0, length: 3),
            redoSelection: NSRange(location: 0, length: 11),
            replacedText: { _ in "" }
        ))

        #expect(plan.lineIndexStrategy == .rebuildOnce)
    }

    @Test func adjacentDeletionsCoalesceIntoAReplayableUndoInsertion() throws {
        let plan = try #require(ProgrammaticEditPlan.prepare(
            edits: [
                TextEdit(range: NSRange(location: 0, length: 1), replacement: ""),
                TextEdit(range: NSRange(location: 1, length: 1), replacement: "")
            ],
            documentLength: 2,
            undoSelection: NSRange(location: 0, length: 2),
            redoSelection: NSRange(location: 0, length: 0),
            replacedText: { range in String(repeating: "a", count: range.length) }
        ))

        #expect(plan.forwardEdits == [
            TextEdit(range: NSRange(location: 0, length: 2), replacement: "")
        ])
        #expect(plan.undoPayload.edits == [
            TextEdit(range: NSRange(location: 0, length: 0), replacement: "aa")
        ])
    }

    @MainActor
    @Test func customEditorCommandsParticipateInNativeUndoAndRedo() throws {
        let suiteName = "SimpleCode.EditorVisibleRangeTests.Undo.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory.appending(path: "SimpleCodeEditorUndo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = AppSettingsStore(defaults: defaults)
        let workspace = WorkspaceModel(
            id: UUID(),
            rootURL: root,
            appSettings: settings,
            workspaceStateStore: WorkspaceStateStore(defaults: defaults, storageKey: "editor-undo.\(UUID().uuidString)")
        )
        let session = EditorDocumentSession(displayName: "Undo.swift")
        session.textStorage.setAttributedString(NSAttributedString(string: "x\ny"))
        session.lineStartIndex.rebuild(from: session.textStorage.string)
        session.enablesSyntaxHighlighting = false

        let textView = CodeTextView()
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView

        let coordinator = CodeEditorRepresentable.Coordinator(
            session: session,
            settings: settings.snapshot,
            workspace: workspace,
            onTextChanged: {}
        )
        coordinator.textView = textView
        coordinator.scrollView = scrollView
        coordinator.attach(session: session, to: textView)
        textView.setSelectedRange(NSRange(location: 0, length: 3))
        let undoManager = try #require(textView.undoManager)
        undoManager.removeAllActions()

        #expect(coordinator.codeTextViewHandleTab(textView, shift: false))
        #expect(textView.string == "    x\n    y")
        #expect(session.lineStartIndex.lineCount == 2)
        #expect(session.lineStartIndex.lineStartUTF16Offset(forLine: 2) == 6)
        #expect(undoManager.canUndo)
        let commandSelection = textView.selectedRange()
        textView.setSelectedRange(NSRange(location: 1, length: 0))

        undoManager.undo()
        #expect(textView.string == "x\ny")
        #expect(session.lineStartIndex.lineStartUTF16Offset(forLine: 2) == 2)
        #expect(undoManager.canRedo)

        undoManager.redo()
        #expect(textView.string == "    x\n    y")
        #expect(session.lineStartIndex.lineStartUTF16Offset(forLine: 2) == 6)
        #expect(textView.selectedRange() == commandSelection)

        undoManager.removeAllActions()
        #expect(coordinator.applyEditorMutation(EditorCommandResult(
            edits: [
                TextEdit(range: NSRange(location: 0, length: 1), replacement: ""),
                TextEdit(range: NSRange(location: 1, length: 1), replacement: "")
            ],
            resultingSelections: [NSRange(location: 0, length: 0)]
        ), to: session))
        #expect(textView.string == "  x\n    y")
        undoManager.undo()
        #expect(textView.string == "    x\n    y")
        undoManager.redo()
        #expect(textView.string == "  x\n    y")
    }

    @MainActor
    @Test func customEditorCommandsUseIncrementalHighlightingWhenParserRevisionIsContinuous() async throws {
        let suiteName = "SimpleCode.EditorVisibleRangeTests.ProgrammaticHighlight.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory.appending(path: "SimpleCodeProgrammaticHighlight-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = AppSettingsStore(defaults: defaults)
        let workspace = WorkspaceModel(
            id: UUID(),
            rootURL: root,
            appSettings: settings,
            workspaceStateStore: WorkspaceStateStore(defaults: defaults, storageKey: "editor-programmatic-highlight.\(UUID().uuidString)")
        )
        defer { workspace.tearDown() }
        let highlighter = RecordingEditorHighlighter()
        let session = EditorDocumentSession(displayName: "Highlight.swift")
        session.textStorage.setAttributedString(NSAttributedString(string: "x"))
        session.highlighter = highlighter
        session.applyInitialHighlighting(HighlightBatch(
            revision: 0,
            coveredRanges: [NSRange(location: 0, length: 1)],
            tokens: []
        ))

        let textView = CodeTextView()
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        let coordinator = CodeEditorRepresentable.Coordinator(
            session: session,
            settings: settings.snapshot,
            workspace: workspace,
            onTextChanged: {}
        )
        coordinator.textView = textView
        coordinator.scrollView = scrollView
        coordinator.attach(session: session, to: textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        #expect(coordinator.codeTextViewHandleTab(textView, shift: false))
        try await Task.sleep(for: .milliseconds(120))

        let calls = await highlighter.snapshot()
        #expect(calls.loadTexts.isEmpty)
        #expect(calls.editTexts == ["    x"])
        coordinator.tearDown()
    }

    @MainActor
    @Test func workspaceCommandsUseTheAttachedTextViewUndoTransaction() throws {
        let suiteName = "SimpleCode.EditorVisibleRangeTests.WorkspaceUndo.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory.appending(path: "SimpleCodeWorkspaceUndo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = AppSettingsStore(defaults: defaults)
        let workspace = WorkspaceModel(
            id: UUID(),
            rootURL: root,
            appSettings: settings,
            workspaceStateStore: WorkspaceStateStore(defaults: defaults, storageKey: "workspace-undo.\(UUID().uuidString)")
        )
        let session = EditorDocumentSession(displayName: "MenuCommand.swift")
        session.textStorage.setAttributedString(NSAttributedString(string: "alpha"))
        session.enablesSyntaxHighlighting = false

        let textView = CodeTextView()
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView

        let coordinator = CodeEditorRepresentable.Coordinator(
            session: session,
            settings: settings.snapshot,
            workspace: workspace,
            onTextChanged: {}
        )
        coordinator.textView = textView
        coordinator.scrollView = scrollView
        coordinator.attach(session: session, to: textView)
        let undoManager = try #require(textView.undoManager)
        undoManager.removeAllActions()

        workspace.applyEditorCommand(
            EditorCommandResult(
                edits: [TextEdit(range: NSRange(location: 0, length: 5), replacement: "beta")],
                resultingSelections: [NSRange(location: 4, length: 0)]
            ),
            session: session
        )

        #expect(textView.string == "beta")
        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(textView.string == "alpha")
    }

    @MainActor
    @Test func eachEditorTabKeepsItsOwnNativeUndoHistory() throws {
        let suiteName = "SimpleCode.EditorVisibleRangeTests.TabUndo.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory.appending(path: "SimpleCodeTabUndo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = AppSettingsStore(defaults: defaults)
        let workspace = WorkspaceModel(
            id: UUID(),
            rootURL: root,
            appSettings: settings,
            workspaceStateStore: WorkspaceStateStore(defaults: defaults, storageKey: "tab-undo.\(UUID().uuidString)")
        )
        let first = EditorDocumentSession(displayName: "First.swift")
        first.textStorage.setAttributedString(NSAttributedString(string: "first"))
        first.enablesSyntaxHighlighting = false
        let second = EditorDocumentSession(displayName: "Second.swift")
        second.textStorage.setAttributedString(NSAttributedString(string: "second"))
        second.enablesSyntaxHighlighting = false

        let textView = CodeTextView()
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        let coordinator = CodeEditorRepresentable.Coordinator(
            session: first,
            settings: settings.snapshot,
            workspace: workspace,
            onTextChanged: {}
        )
        coordinator.textView = textView
        coordinator.scrollView = scrollView

        coordinator.attach(session: first, to: textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(coordinator.codeTextViewHandleTab(textView, shift: false))
        #expect(first.undoManager.canUndo)

        coordinator.attach(session: second, to: textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(coordinator.codeTextViewHandleTab(textView, shift: false))
        #expect(second.undoManager.canUndo)
        second.undoManager.undo()
        #expect(second.textStorage.string == "second")

        coordinator.attach(session: first, to: textView)
        first.undoManager.undo()
        #expect(first.textStorage.string == "first")
    }
}
