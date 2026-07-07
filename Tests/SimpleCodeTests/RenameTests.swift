import Foundation
import Testing
@testable import SimpleCode

@Suite(.serialized)
@MainActor
struct RenameTests {
    @Test func normalRename() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = dir.appendingPathComponent("Old.swift")
        try "x".write(to: source, atomically: true, encoding: .utf8)

        let service = FileOperationService()
        let result = try await service.rename(item: source, to: "New.swift")
        #expect(FileManager.default.fileExists(atPath: result.url.path))
        #expect(!FileManager.default.fileExists(atPath: source.path))
    }

    @Test func caseOnlyRename() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = dir.appendingPathComponent("case.swift")
        try "x".write(to: source, atomically: true, encoding: .utf8)

        let service = FileOperationService()
        let result = try await service.rename(item: source, to: "CASE.swift")
        #expect(FileManager.default.fileExists(atPath: result.url.path))
        #expect(result.url.lastPathComponent == "CASE.swift")
    }

    @Test func renameUpdatesOpenDocumentPath() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = dir.appendingPathComponent("Open.swift")
        try "content".write(to: source, atomically: true, encoding: .utf8)

        let store = OpenDocumentsStore()
        await store.open(url: source)
        let session = store.activeSession!

        let service = FileOperationService()
        let result = try await service.rename(item: source, to: "Renamed.swift")
        store.updatePaths(from: source, to: result.url)
        #expect(session.fileURL == result.url)
        #expect(session.displayName == "Renamed.swift")
    }

    @Test func collisionThrows() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let a = dir.appendingPathComponent("A.swift")
        let b = dir.appendingPathComponent("B.swift")
        try "a".write(to: a, atomically: true, encoding: .utf8)
        try "b".write(to: b, atomically: true, encoding: .utf8)

        let service = FileOperationService()
        await #expect(throws: FileOperationError.nameCollision) {
            try await service.rename(item: a, to: "B.swift")
        }
    }
}
