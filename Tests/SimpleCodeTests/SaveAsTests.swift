import Foundation
import Testing
import UniformTypeIdentifiers
@testable import SimpleCode

@MainActor
final class MockSavePanelCoordinator: SavePanelCoordinating {
    var presentedURL: URL?
    var confirmOverwriteResult = true
    private(set) var presentCount = 0
    private(set) var confirmCount = 0

    func presentSavePanel(
        suggestedDirectory: URL,
        suggestedName: String,
        allowedContentTypes: [UTType]
    ) async -> URL? {
        presentCount += 1
        return presentedURL
    }

    func confirmOverwrite(for url: URL) async -> Bool {
        confirmCount += 1
        return confirmOverwriteResult
    }
}

@Suite(.serialized)
@MainActor
struct SaveAsTests {
    @Test func saveAsWritesToNewURL() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = dir.appendingPathComponent("Original.swift")
        try "let x = 1\n".write(to: source, atomically: true, encoding: .utf8)

        let destination = dir.appendingPathComponent("Copy.swift")
        let store = OpenDocumentsStore()
        let mock = MockSavePanelCoordinator()
        mock.presentedURL = destination
        store.saveAsCoordinator = mock

        await store.open(url: source)
        let session = store.activeSession!
        session.textStorage.mutableString.setString("let x = 2\n")
        session.markDirty()

        try await store.saveAs(session: session)
        #expect(FileManager.default.fileExists(atPath: destination.path))
        #expect(try String(contentsOf: destination, encoding: .utf8) == "let x = 2\n")
        #expect(session.fileURL == destination)
        #expect(!session.isDirty)
    }

    @Test func saveAsCancelPreservesState() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = dir.appendingPathComponent("Keep.swift")
        try "a".write(to: source, atomically: true, encoding: .utf8)

        let store = OpenDocumentsStore()
        let mock = MockSavePanelCoordinator()
        mock.presentedURL = nil
        store.saveAsCoordinator = mock

        await store.open(url: source)
        let session = store.activeSession!
        session.markDirty()

        do {
            try await store.saveAs(session: session)
            Issue.record("Expected cancellation")
        } catch FileOperationError.cancelled {
            #expect(session.fileURL == source)
            #expect(session.isDirty)
        }
    }

    @Test func saveAsDestinationAlreadyOpenActivatesExisting() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let a = dir.appendingPathComponent("A.swift")
        let b = dir.appendingPathComponent("B.swift")
        try "a".write(to: a, atomically: true, encoding: .utf8)
        try "b".write(to: b, atomically: true, encoding: .utf8)

        let store = OpenDocumentsStore()
        await store.open(url: a)
        await store.open(url: b)
        let bID = store.activeSessionID

        let mock = MockSavePanelCoordinator()
        mock.presentedURL = a
        store.saveAsCoordinator = mock

        let session = store.session(for: b)!
        do {
            try await store.saveAs(session: session)
            Issue.record("Expected collision")
        } catch FileOperationError.nameCollision {
            #expect(store.activeSessionID != bID)
            #expect(store.session(for: a) != nil)
        }
    }
}
