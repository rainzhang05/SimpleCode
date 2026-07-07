import Foundation

@MainActor
@Observable
final class WorkspaceTrustController {
    private let workspaceID: UUID
    private let stateStore: WorkspaceStateStore
    private(set) var effectiveTrust: WorkspaceTrustState

    init(workspaceID: UUID, stateStore: WorkspaceStateStore, provenance: WorkspaceOpenProvenance, rootURL: URL) {
        self.workspaceID = workspaceID
        self.stateStore = stateStore

        let currentIdentity = FileIdentity(url: rootURL).key
        var persisted = stateStore.state(for: workspaceID)

        if let storedIdentity = persisted.rootFilesystemIdentity, storedIdentity != currentIdentity {
            persisted.trust = .untrusted
        }
        persisted.rootFilesystemIdentity = currentIdentity

        switch provenance {
        case .userCreated:
            persisted.trust = .trusted
        case .cloned:
            persisted.trust = .untrusted
        case .openedExisting:
            break
        }

        stateStore.setState(persisted, for: workspaceID)
        self.effectiveTrust = persisted.trust
    }

    var isTrusted: Bool { effectiveTrust.isTrusted }

    func markTrusted() {
        stateStore.updateTrust(for: workspaceID, trust: .trusted)
        effectiveTrust = .trusted
    }

    func markUntrusted() {
        stateStore.updateTrust(for: workspaceID, trust: .untrusted)
        effectiveTrust = .untrusted
    }
}
