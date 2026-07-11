import AppKit
import Foundation
import Testing
@testable import SimpleCode

struct EditorVisibleRangeTests {
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
