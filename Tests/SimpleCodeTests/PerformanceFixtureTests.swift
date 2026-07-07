import Foundation
import Testing
@testable import SimpleCode

struct PerformanceFixtureGenerator {
    static func createLargeWorkspace(at root: URL, fileCount: Int = 2000, directoryCount: Int = 200) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let excluded = ["node_modules", ".git", ".build", "DerivedData", ".hidden"]
        for name in excluded {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
            if name == "node_modules" {
                try FileManager.default.createDirectory(
                    at: root.appendingPathComponent("node_modules/pkg"),
                    withIntermediateDirectories: true
                )
                try "pkg".write(
                    to: root.appendingPathComponent("node_modules/pkg/index.js"),
                    atomically: true,
                    encoding: .utf8
                )
            }
        }

        let realDir = root.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked"),
            withDestinationURL: realDir
        )

        var created = 0
        var dirIndex = 0
        while created < fileCount {
            let depth = dirIndex % 6
            var path = root.appendingPathComponent("dirs/dir\(dirIndex)")
            for level in 0..<depth {
                path = path.appendingPathComponent("level\(level)")
            }
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            let filesInDir = min(10, fileCount - created)
            for fileIndex in 0..<filesInDir {
                let file = path.appendingPathComponent("File\(fileIndex).swift")
                try "let value = \(created)\n".write(to: file, atomically: true, encoding: .utf8)
                created += 1
            }
            dirIndex += 1
        }

        let large = root.appendingPathComponent("Large.swift")
        try String(repeating: "let big = 1\n", count: 450_000).write(to: large, atomically: true, encoding: .utf8)

        for index in 0..<12 {
            let editable = root.appendingPathComponent("Editable\(index).swift")
            try "var e\(index) = \(index)".write(to: editable, atomically: true, encoding: .utf8)
        }
    }
}

struct PerformanceFixtureTests {
    @Test func largeWorkspaceRootLoadsQuickly() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Perf-\(UUID().uuidString)")
        try PerformanceFixtureGenerator.createLargeWorkspace(at: root)
        let service = WorkspaceFileTreeService()
        let start = Date()
        let listing = await service.listDirectory(at: root, workspaceRoot: root, showHidden: false)
        let elapsed = Date().timeIntervalSince(start)
        #expect(!listing.children.isEmpty)
        #expect(elapsed < 3.0)
        let names = Set(listing.children.map(\.name))
        #expect(!names.contains("node_modules"))
        #expect(names.contains("dirs") || names.contains("Editable0.swift"))
    }

    @Test func symlinkDirectoryNotFollowed() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "PerfSym-\(UUID().uuidString)")
        try PerformanceFixtureGenerator.createLargeWorkspace(at: root, fileCount: 20, directoryCount: 5)
        let service = WorkspaceFileTreeService()
        let listing = await service.listDirectory(at: root, workspaceRoot: root, showHidden: false)
        let linked = listing.children.first { $0.name == "linked" }
        #expect(linked?.isSymlink == true)
        guard let linked else { return }
        let childListing = await service.listDirectory(at: linked.url, workspaceRoot: root, showHidden: false)
        #expect(childListing.children.isEmpty)
    }
}
