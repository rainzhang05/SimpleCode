import AppKit
import Foundation
import Testing
@testable import SimpleCode

struct EditorVisibleRangeTests {
    @MainActor
    @Test func currentLineHighlightSurvivesBaseBackgroundPaint() throws {
        let originalAppearance = SettingsColorResolver.appearance
        var testAppearance = originalAppearance
        let white = StoredColor(red: 1, green: 1, blue: 1)
        let marker = StoredColor(red: 0.12, green: 0.83, blue: 0.29)
        testAppearance.editorBackground = StoredColorPair(light: white, dark: white)
        testAppearance.editorCurrentLine = StoredColorPair(light: marker, dark: marker)
        SettingsColorResolver.updateSnapshot(testAppearance)
        defer { SettingsColorResolver.updateSnapshot(originalAppearance) }

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
            settings: settings,
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
            settings: settings,
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
        session.textStorage.setAttributedString(NSAttributedString(string: "x"))
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
            settings: settings,
            workspace: workspace,
            onTextChanged: {}
        )
        coordinator.textView = textView
        coordinator.scrollView = scrollView
        coordinator.attach(session: session, to: textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        let undoManager = try #require(textView.undoManager)
        undoManager.removeAllActions()

        #expect(coordinator.codeTextViewHandleTab(textView, shift: false))
        #expect(textView.string == "    x")
        #expect(undoManager.canUndo)

        undoManager.undo()
        #expect(textView.string == "x")
        #expect(undoManager.canRedo)

        undoManager.redo()
        #expect(textView.string == "    x")
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
            settings: settings,
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
            settings: settings,
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
