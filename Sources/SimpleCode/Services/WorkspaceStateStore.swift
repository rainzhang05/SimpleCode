import Foundation

struct WorkspacePersistedState: Codable, Equatable, Sendable {
    var runConfiguration: RunConfiguration

    static let `default` = WorkspacePersistedState(
        runConfiguration: .default
    )
}

/// Per-workspace persisted state keyed by stable `WorkspaceRecord.id`.
@MainActor
final class WorkspaceStateStore {
    private let defaults: UserDefaults
    private let storageKey: String
    private var states: [UUID: WorkspacePersistedState]

    init(defaults: UserDefaults = .standard, storageKey: String = "workspaceState.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        self.states = Self.decode(from: defaults, key: storageKey)
    }

    func state(for workspaceID: UUID) -> WorkspacePersistedState {
        states[workspaceID] ?? .default
    }

    func setState(_ state: WorkspacePersistedState, for workspaceID: UUID) {
        states[workspaceID] = state
        persist()
    }

    func updateRunConfiguration(
        for workspaceID: UUID,
        _ transform: (inout RunConfiguration) -> Void
    ) {
        var state = state(for: workspaceID)
        transform(&state.runConfiguration)
        setState(state, for: workspaceID)
    }

    private func persist() {
        let encoder = JSONEncoder()
        let stringKeyed = Dictionary(uniqueKeysWithValues: states.map { ($0.key.uuidString, $0.value) })
        guard let data = try? encoder.encode(stringKeyed) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func decode(from defaults: UserDefaults, key: String) -> [UUID: WorkspacePersistedState] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        let decoder = JSONDecoder()
        guard let raw = try? decoder.decode([String: WorkspacePersistedState].self, from: data) else {
            return [:]
        }
        var result: [UUID: WorkspacePersistedState] = [:]
        for (key, value) in raw {
            guard let uuid = UUID(uuidString: key) else { continue }
            result[uuid] = value
        }
        return result
    }
}
