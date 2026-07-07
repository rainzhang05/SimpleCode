import Foundation
import Testing
@testable import SimpleCode

@Suite(.serialized)
@MainActor
struct WorkspaceTrustTests {
    private func makeStore() -> WorkspaceStateStore {
        let suiteName = "com.simplecode.tests.trust.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return WorkspaceStateStore(defaults: defaults, storageKey: "trust.\(UUID())")
    }

    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "Trust-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func newCloneUntrusted() throws {
        let store = makeStore()
        let id = UUID()
        let root = try makeRoot()
        let trust = WorkspaceTrustController(workspaceID: id, stateStore: store, provenance: .cloned, rootURL: root)
        #expect(!trust.isTrusted)
    }

    @Test func newlyOpenedFolderUntrusted() throws {
        let store = makeStore()
        let id = UUID()
        let root = try makeRoot()
        let trust = WorkspaceTrustController(workspaceID: id, stateStore: store, provenance: .openedExisting, rootURL: root)
        #expect(!trust.isTrusted)
    }

    @Test func userCreatedFolderTrusted() throws {
        let store = makeStore()
        let id = UUID()
        let root = try makeRoot()
        let trust = WorkspaceTrustController(workspaceID: id, stateStore: store, provenance: .userCreated, rootURL: root)
        #expect(trust.isTrusted)
    }

    @Test func trustAndRevocation() throws {
        let store = makeStore()
        let id = UUID()
        let root = try makeRoot()
        let trust = WorkspaceTrustController(workspaceID: id, stateStore: store, provenance: .openedExisting, rootURL: root)
        trust.markTrusted()
        #expect(trust.isTrusted)
        trust.markUntrusted()
        #expect(!trust.isTrusted)
    }

    @Test func identityMismatchInvalidatesOnReopen() throws {
        let store = makeStore()
        let id = UUID()
        let root1 = try makeRoot()
        store.updateRootIdentity(for: id, identity: "path:/fake/old")
        store.updateTrust(for: id, trust: .trusted)

        let trust = WorkspaceTrustController(workspaceID: id, stateStore: store, provenance: .openedExisting, rootURL: root1)
        #expect(!trust.isTrusted)
    }

    @Test func trustPersistsAcrossReopen() throws {
        let store = makeStore()
        let id = UUID()
        let root = try makeRoot()
        let first = WorkspaceTrustController(workspaceID: id, stateStore: store, provenance: .openedExisting, rootURL: root)
        first.markTrusted()

        let second = WorkspaceTrustController(workspaceID: id, stateStore: store, provenance: .openedExisting, rootURL: root)
        #expect(second.isTrusted)
    }

    @Test func runOnceDoesNotPersistOnReopen() throws {
        let store = makeStore()
        let id = UUID()
        let root = try makeRoot()
        let trust = WorkspaceTrustController(workspaceID: id, stateStore: store, provenance: .openedExisting, rootURL: root)
        #expect(!trust.isTrusted)

        let reopened = WorkspaceTrustController(workspaceID: id, stateStore: store, provenance: .openedExisting, rootURL: root)
        #expect(!reopened.isTrusted)
    }

    @Test func revocationRestoresGateOnReopen() throws {
        let store = makeStore()
        let id = UUID()
        let root = try makeRoot()
        let trust = WorkspaceTrustController(workspaceID: id, stateStore: store, provenance: .openedExisting, rootURL: root)
        trust.markTrusted()
        trust.markUntrusted()

        let reopened = WorkspaceTrustController(workspaceID: id, stateStore: store, provenance: .openedExisting, rootURL: root)
        #expect(!reopened.isTrusted)
    }

    @Test func ordinaryEditsDoNotInvalidateIdentity() throws {
        let store = makeStore()
        let id = UUID()
        let root = try makeRoot()
        let trust = WorkspaceTrustController(workspaceID: id, stateStore: store, provenance: .openedExisting, rootURL: root)
        trust.markTrusted()
        let identityBefore = FileIdentity(url: root).key

        try "edited".write(to: root.appending(path: "file.txt"), atomically: true, encoding: .utf8)

        let reopened = WorkspaceTrustController(workspaceID: id, stateStore: store, provenance: .openedExisting, rootURL: root)
        #expect(reopened.isTrusted)
        #expect(FileIdentity(url: root).key == identityBefore)
    }
}
