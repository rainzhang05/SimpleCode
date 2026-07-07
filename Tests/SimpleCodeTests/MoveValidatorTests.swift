import Foundation
import Testing
@testable import SimpleCode

struct MoveValidatorTests {
    @Test func rejectsMoveIntoDescendant() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let parent = root.appendingPathComponent("Parent")
        let child = parent.appendingPathComponent("Child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)

        let result = MoveValidator.validate(source: parent, destinationDirectory: child, workspaceRoot: root)
        #expect(result == .failure(.moveIntoDescendant))
    }

    @Test func rejectsCollision() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("A.txt")
        let destDir = root.appendingPathComponent("Dir")
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        try "a".write(to: source, atomically: true, encoding: .utf8)
        try "b".write(to: destDir.appendingPathComponent("A.txt"), atomically: true, encoding: .utf8)

        let result = MoveValidator.validate(source: source, destinationDirectory: destDir, workspaceRoot: root)
        #expect(result == .failure(.nameCollision))
    }

    @Test func acceptsValidMove() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("MoveMe.txt")
        let destDir = root.appendingPathComponent("Target")
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        try "x".write(to: source, atomically: true, encoding: .utf8)

        let result = MoveValidator.validate(source: source, destinationDirectory: destDir, workspaceRoot: root)
        guard case .success(let target) = result else {
            Issue.record("Expected success")
            return
        }
        #expect(target.lastPathComponent == "MoveMe.txt")
    }

    @Test func rejectsNoOp() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("Same.txt")
        try "x".write(to: source, atomically: true, encoding: .utf8)

        let result = MoveValidator.validate(source: source, destinationDirectory: root, workspaceRoot: root)
        #expect(result == .failure(.noOp))
    }
}
