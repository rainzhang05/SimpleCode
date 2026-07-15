import Foundation
import Testing
@testable import SimpleCode

@Suite(.serialized)
@MainActor
struct DocumentWatcherTests {
    @Test func detectsCleanExternalModification() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Watch.swift")
        try "v1".write(to: file, atomically: true, encoding: .utf8)

        let store = OpenDocumentsStore()
        await store.open(url: file)
        let session = store.activeSession!
        #expect(session.externalChangeState == .none)

        try await Task.sleep(for: .milliseconds(200))
        try "v2".write(to: file, atomically: true, encoding: .utf8)

        try await waitUntil(timeout: 3) {
            session.externalChangeState == .cleanReloadAvailable
        }
    }

    @Test func detectsDirtyConflict() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Dirty.swift")
        try "v1".write(to: file, atomically: true, encoding: .utf8)

        let store = OpenDocumentsStore()
        await store.open(url: file)
        let session = store.activeSession!
        session.textStorage.mutableString.setString("v1-edited")
        session.markDirty()

        try await Task.sleep(for: .milliseconds(200))
        try "v2".write(to: file, atomically: true, encoding: .utf8)

        try await waitUntil(timeout: 3) {
            session.externalChangeState == .dirtyConflict
        }
    }

    @Test func stopWatchingOnClose() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Close.swift")
        try "x".write(to: file, atomically: true, encoding: .utf8)

        let store = OpenDocumentsStore()
        await store.open(url: file)
        let id = store.activeSessionID!
        _ = store.close(sessionID: id, force: true)

        try "y".write(to: file, atomically: true, encoding: .utf8)
        #expect(store.sessions.isEmpty)
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Condition not met within timeout")
    }
}
