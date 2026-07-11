import Foundation
import Testing
@testable import SimpleCode

struct WorkspaceTreeExclusionsTests {
    @Test func showsAllDirectoriesUnlessTheUserExcludesThem() {
        #expect(!WorkspaceTreeExclusions.shouldExclude(directoryName: ".git", isWorkspaceRoot: false))
        #expect(!WorkspaceTreeExclusions.shouldExclude(directoryName: "node_modules", isWorkspaceRoot: false))
        #expect(WorkspaceTreeExclusions.shouldExclude(
            directoryName: ".git",
            relativePath: ".git",
            isWorkspaceRoot: false,
            userPatterns: [".git"]
        ))
    }

    @Test func neverExcludesWorkspaceRoot() {
        #expect(!WorkspaceTreeExclusions.shouldExclude(directoryName: ".git", isWorkspaceRoot: true))
    }

    @MainActor
    @Test func fileTreeCachesFlattenedVisibleRows() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "SimpleCodeTree-\(UUID().uuidString)")
        let source = root.appending(path: "Sources")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "let app = 1".write(to: source.appending(path: "App.swift"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let tree = FileTreeModel(workspaceRoot: root)
        await tree.loadRoot()
        #expect(tree.visibleRows.map(\.node.name) == ["Sources"])

        let sourceID = try #require(tree.rootChildren.first?.id)
        await tree.toggleExpansion(for: sourceID)
        #expect(tree.visibleRows.map(\.node.name) == ["Sources", "App.swift"])

        await tree.toggleExpansion(for: sourceID)
        #expect(tree.visibleRows.map(\.node.name) == ["Sources"])
    }
}

struct TextEncodingTests {
    @Test func detectsUTF8BOM() {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("hello".utf8)
        let result = TextEncodingDetector.detect(in: data)
        #expect(result?.encoding == .utf8WithBOM)
    }

    @Test func detectsUTF16LEBOM() {
        let data = Data([0xFF, 0xFE, 0x41, 0x00])
        let result = TextEncodingDetector.detect(in: data)
        #expect(result?.encoding == .utf16LittleEndian)
    }

    @Test func roundTripsUTF8() throws {
        let text = "line\n"
        let request = FileContentWriter.WriteRequest(
            url: URL(fileURLWithPath: "/tmp/test.swift"),
            text: text,
            encoding: .utf8,
            includeBOM: false,
            lineEnding: .lf
        )
        let data = try FileContentWriter.serialize(request)
        #expect(String(data: data, encoding: .utf8) == text)
    }
}

struct LineEndingTests {
    @Test func detectsLF() {
        #expect(LineEndingDetector.detect(in: "a\nb") == .lf)
    }

    @Test func detectsCRLF() {
        #expect(LineEndingDetector.detect(in: "a\r\nb") == .crlf)
    }

    @Test func detectsMixed() {
        #expect(LineEndingDetector.detect(in: "a\nb\r\nc") == .mixed)
    }
}

struct BinaryDetectionTests {
    @Test func detectsNULBytes() {
        #expect(BinaryDetector.isProbablyBinary(Data([0, 1, 2, 3])))
    }

    @Test func textIsNotBinary() {
        #expect(!BinaryDetector.isProbablyBinary(Data("print(\"hi\")".utf8)))
    }
}

struct FileSizeThresholdTests {
    @Test func normalFilePolicy() {
        #expect(FileSizeThresholds.openPolicy(forByteCount: 1_000) == .normal)
    }

    @Test func largeFilePolicy() {
        #expect(FileSizeThresholds.openPolicy(forByteCount: 6 * 1_024 * 1_024) == .warnLargeFile)
    }
}

struct FileIdentityTests {
    @Test func samePathProducesSameIdentity() {
        let url = URL(fileURLWithPath: "/tmp/a.swift")
        #expect(FileIdentity(url: url) == FileIdentity(url: url))
    }
}
