import Foundation
import Testing
@testable import SimpleCode

@Suite(.serialized)
@MainActor
struct OpenDocumentsStoreTests {
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
        store.reopenLastClosed()
        #expect(store.sessions.count == 1)
    }
}
