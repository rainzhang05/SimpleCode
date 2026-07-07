import Foundation
import Testing
@testable import SimpleCode

struct WorkspaceFileTreeServiceTests {
    @Test func foldersSortBeforeFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("BFolder"), withIntermediateDirectories: true)
        try "z".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let service = WorkspaceFileTreeService()
        let listing = await service.listDirectory(at: root, workspaceRoot: root, showHidden: false)
        #expect(listing.children.first?.isDirectory == true)
    }

    @Test func excludesNodeModules() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        let service = WorkspaceFileTreeService()
        let listing = await service.listDirectory(at: root, workspaceRoot: root, showHidden: false)
        #expect(listing.children.isEmpty)
    }
}

struct FileOperationServiceTests {
    @Test func createAndRenameFile() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let service = FileOperationService()
        let created = try await service.createFile(at: root, name: "A.swift")
        let renamed = try await service.rename(item: created.url, to: "B.swift")
        #expect(FileManager.default.fileExists(atPath: renamed.url.path))
    }

    @Test func rejectsMoveIntoDescendant() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let parent = root.appendingPathComponent("Parent")
        let child = parent.appendingPathComponent("Child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let service = FileOperationService()
        do {
            _ = try await service.move(item: parent, to: child)
            Issue.record("Expected move into descendant to fail")
        } catch FileOperationError.moveIntoDescendant {
            #expect(true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
