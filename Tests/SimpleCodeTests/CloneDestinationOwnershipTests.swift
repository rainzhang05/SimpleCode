import Foundation
import Testing
@testable import SimpleCode

@Suite(.serialized)
struct CloneDestinationOwnershipTests {
    private func makeTemp() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "CloneOwn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func ownedPartialDestinationRemovedAfterProcessExit() throws {
        let base = try makeTemp()
        let dest = base.appending(path: "owned")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        var ownership = CloneDestinationOwnership(destinationURL: dest, existedBeforeClone: false)
        ownership.captureIdentityIfDestinationAppeared()
        #expect(ownership.canRemovePartialDestination(processHasExited: true))
        try FileManager.default.removeItem(at: dest)
        #expect(!FileManager.default.fileExists(atPath: dest.path))
    }

    @Test func preExistingEmptyDirectoryNotRemoved() throws {
        let base = try makeTemp()
        let dest = base.appending(path: "existing")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        let ownership = CloneDestinationOwnership(destinationURL: dest, existedBeforeClone: true)
        #expect(!ownership.canRemovePartialDestination(processHasExited: true))
    }

    @Test func preExistingNonEmptyDirectoryNotRemoved() throws {
        let base = try makeTemp()
        let dest = base.appending(path: "existing")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try "marker".write(to: dest.appending(path: "marker.txt"), atomically: true, encoding: .utf8)

        let ownership = CloneDestinationOwnership(destinationURL: dest, existedBeforeClone: true)
        #expect(!ownership.canRemovePartialDestination(processHasExited: true))
    }

    @Test func refusesCleanupWhileProcessRunning() throws {
        let base = try makeTemp()
        let dest = base.appending(path: "running")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        var ownership = CloneDestinationOwnership(destinationURL: dest, existedBeforeClone: false)
        ownership.captureIdentityIfDestinationAppeared()
        #expect(!ownership.canRemovePartialDestination(processHasExited: false))
    }

    @Test func replacedDestinationNotRemoved() throws {
        let base = try makeTemp()
        let dest = base.appending(path: "clone-target")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        var ownership = CloneDestinationOwnership(destinationURL: dest, existedBeforeClone: false)
        ownership.captureIdentityIfDestinationAppeared()

        try FileManager.default.removeItem(at: dest)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        #expect(!ownership.canRemovePartialDestination(processHasExited: true))
    }

    @Test func symlinkDestinationNotRemovedWithoutMatchingInode() throws {
        let base = try makeTemp()
        let real = base.appending(path: "real")
        let link = base.appending(path: "link")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        var ownership = CloneDestinationOwnership(destinationURL: link, existedBeforeClone: false)
        ownership.captureIdentityIfDestinationAppeared()
        #expect(!ownership.canRemovePartialDestination(processHasExited: true) || ownership.inodeAfterGitCreate != nil)
    }
}
