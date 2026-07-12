import AppKit
import Foundation
import Testing
@testable import SimpleCode

@Suite(.serialized)
@MainActor
struct OpenDocumentsStoreTests {
    private actor DeferredFileContentLoader: FileContentLoading {
        private var continuations: [URL: CheckedContinuation<LoadedFileContent, Error>] = [:]

        func metadata(for url: URL) throws -> FileMetadata {
            FileMetadata(byteCount: 64, openPolicy: .normal)
        }

        func load(url: URL, choice: LargeFileOpenChoice?) async throws -> LoadedFileContent {
            try await withCheckedThrowingContinuation { continuation in
                continuations[url] = continuation
            }
        }

        func hasPendingLoad(for url: URL) -> Bool {
            continuations[url] != nil
        }

        func resolve(_ url: URL, text: String) {
            let content = LoadedFileContent(
                text: text,
                encoding: .utf8,
                hadBOM: false,
                lineEnding: .lf,
                byteCount: Int64(text.utf8.count),
                modificationDate: nil,
                fileResourceIdentifier: nil,
                language: LanguageDetector.detect(url: url, content: text),
                openPolicy: .normal
            )
            continuations.removeValue(forKey: url)?.resume(returning: content)
        }
    }

    @Test func duplicateOpenActivatesExistingTab() async throws {
        let store = OpenDocumentsStore()
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("A.swift")
        try "let a = 1".write(to: file, atomically: true, encoding: .utf8)

        await store.open(url: file)
        let firstID = store.activeSessionID
        await store.open(url: file)
        #expect(store.sessions.count == 1)
        #expect(store.activeSessionID == firstID)
    }

    @Test func dirtyStateTransitions() async throws {
        let session = EditorDocumentSession(displayName: "T.swift")
        session.textStorage.setAttributedString(NSAttributedString(string: "x"))
        #expect(!session.isDirty)
        session.markDirty()
        #expect(session.isDirty)
    }

    @Test func reopenRecentlyClosed() async throws {
        let store = OpenDocumentsStore()
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Closed.swift")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        await store.open(url: file)
        let id = store.activeSessionID!
        _ = store.close(sessionID: id, force: true)
        await store.reopenLastClosed()
        #expect(store.sessions.count == 1)
    }

    @Test func loadedSwiftDocumentPublishesWithInitialSyntaxAlreadyApplied() async throws {
        let store = OpenDocumentsStore()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Prepared.swift")
        try "let answer = 42\n".write(to: file, atomically: true, encoding: .utf8)

        await store.open(url: file)

        let session = try #require(store.activeSession)
        #expect(session.loadState == .loaded)
        #expect(session.highlighter != nil)
        #expect(session.hasAppliedSyntaxHighlighting)
        let keywordColor = session.textStorage.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor
        #expect(keywordColor != nil)
    }

    @Test func recentlyClosedRecordDoesNotRetainTheEditorSession() async throws {
        let store = OpenDocumentsStore()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Closed.swift")
        try "let closed = true\n".write(to: file, atomically: true, encoding: .utf8)
        await store.open(url: file)

        weak var releasedSession: EditorDocumentSession?
        let closedID: UUID
        do {
            let session = try #require(store.activeSession)
            releasedSession = session
            closedID = session.id
        }

        #expect(store.close(sessionID: closedID, force: true))
        #expect(store.recentlyClosed.count == 1)
        #expect(releasedSession == nil)

        await store.reopenLastClosed()
        #expect(store.activeSession?.fileURL?.standardizedFileURL == file.standardizedFileURL)
    }

    @Test func rapidFileSelectionKeepsOnlyTheLatestOpenRequest() async throws {
        let loader = DeferredFileContentLoader()
        let store = OpenDocumentsStore(loader: loader)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let first = directory.appendingPathComponent("First.swift")
        let second = directory.appendingPathComponent("Second.swift")

        let firstTask = Task { @MainActor in await store.open(url: first) }
        await waitForPendingLoad(of: first, in: loader)
        let secondTask = Task { @MainActor in await store.open(url: second) }
        await waitForPendingLoad(of: second, in: loader)

        await loader.resolve(first, text: "let first = 1")
        await loader.resolve(second, text: "let second = 2")
        await firstTask.value
        await secondTask.value

        #expect(store.sessions.count == 1)
        #expect(store.activeSession?.fileURL?.standardizedFileURL == second.standardizedFileURL)
        #expect(store.activeSession?.textStorage.string == "let second = 2")
    }

    private func waitForPendingLoad(of url: URL, in loader: DeferredFileContentLoader) async {
        for _ in 0..<100 {
            if await loader.hasPendingLoad(for: url) { return }
            await Task.yield()
        }
        Issue.record("Timed out waiting for deferred file load")
    }
}
