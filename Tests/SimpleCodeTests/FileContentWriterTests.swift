import Foundation
import Testing
@testable import SimpleCode

struct FileContentWriterTests {
    @Test func atomicWritePreservesOriginalOnFailure() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Atomic.txt")
        try "original".write(to: file, atomically: true, encoding: .utf8)

        let request = FileContentWriter.WriteRequest(
            url: file,
            text: "updated",
            encoding: .utf8,
            includeBOM: false,
            lineEnding: .lf
        )
        _ = try FileContentWriter.writeAtomically(request)
        #expect(try String(contentsOf: file, encoding: .utf8) == "updated")
    }

    @Test func tempFileInSameDirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Perms.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)

        let request = FileContentWriter.WriteRequest(
            url: file,
            text: "y",
            encoding: .utf8,
            includeBOM: false,
            lineEnding: .lf
        )
        _ = try FileContentWriter.writeAtomically(request)

        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        let permissions = attrs[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o644)
    }

    @Test func symlinkWriteTargetsLinkPath() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("target.txt")
        let link = dir.appendingPathComponent("link.txt")
        try "target".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let request = FileContentWriter.WriteRequest(
            url: link,
            text: "via link",
            encoding: .utf8,
            includeBOM: false,
            lineEnding: .lf
        )
        _ = try FileContentWriter.writeAtomically(request)
        #expect(try String(contentsOf: target, encoding: .utf8) == "via link")
        #expect(try String(contentsOf: link, encoding: .utf8) == "via link")
    }

    @Test func localizedErrorMessages() {
        #expect(FileOperationError.externalModificationConflict.errorDescription?.isEmpty == false)
        #expect(FileOperationError.nameCollision.errorDescription?.isEmpty == false)
    }
}
