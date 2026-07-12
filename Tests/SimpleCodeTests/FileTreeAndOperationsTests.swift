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
        let listing = await service.listDirectory(at: root, workspaceRoot: root)
        #expect(listing.children.first?.isDirectory == true)
    }

    @Test func includesDotfilesWithoutAVisibilityOption() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".config"),
            withIntermediateDirectories: true
        )
        try "token".write(to: root.appendingPathComponent(".env"), atomically: true, encoding: .utf8)

        let service = WorkspaceFileTreeService()
        let listing = await service.listDirectory(at: root, workspaceRoot: root)

        #expect(Set(listing.children.map(\.name)).isSuperset(of: [".config", ".env"]))
    }

    @Test func includesProjectDirectoriesUnlessTheUserExcludesThem() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        let service = WorkspaceFileTreeService()
        let listing = await service.listDirectory(at: root, workspaceRoot: root)
        #expect(listing.children.map(\.name) == ["node_modules"])

        let filtered = await service.listDirectory(
            at: root,
            workspaceRoot: root,
            userPatterns: ["node_modules"]
        )
        #expect(filtered.children.isEmpty)
    }
}

@MainActor
struct FileTreeModelRefreshTests {
    @Test func changedExclusionGenerationRejectsStaleLoad() {
        var currentGeneration = FileTreeExclusionGeneration()
        let loadGeneration = currentGeneration

        currentGeneration.advance()

        #expect(!currentGeneration.permitsCommit(from: loadGeneration))
        #expect(currentGeneration.permitsCommit(from: currentGeneration))
    }

    @Test func exclusionRefreshPreservesExpandedDirectories() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let sources = root.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Generated"),
            withIntermediateDirectories: true
        )
        try "let value = 1".write(
            to: sources.appendingPathComponent("App.swift"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let tree = FileTreeModel(workspaceRoot: root)
        await tree.loadRoot()
        let sourcesID = try #require(tree.rootChildren.first { $0.name == "Sources" }?.id)
        await tree.toggleExpansion(for: sourcesID)

        #expect(tree.applyUserExclusions(["Generated"]))
        #expect(!tree.applyUserExclusions(["Generated"]))
        await tree.refresh()

        #expect(tree.expandedNodeIDs.contains(sourcesID))
        #expect(tree.visibleRows.map(\.node.name).contains("App.swift"))
        #expect(!tree.rootChildren.map(\.name).contains("Generated"))
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
