import Foundation
import Testing
@testable import SimpleCode

@Suite(.serialized)
@MainActor
struct RunConfigurationStoreTests {
    private func makeStore() -> (WorkspaceStateStore, UserDefaults) {
        let suiteName = "com.simplecode.tests.runconfig.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (WorkspaceStateStore(defaults: defaults, storageKey: "test.\(UUID())"), defaults)
    }

    @Test func perWorkspacePersistence() {
        let (store, _) = makeStore()
        let id1 = UUID()
        let id2 = UUID()

        store.updateRunConfiguration(for: id1) { $0.command = "swift run"; $0.isCommandExplicit = true }
        store.updateRunConfiguration(for: id2) { $0.command = "make"; $0.isCommandExplicit = true }

        #expect(store.state(for: id1).runConfiguration.command == "swift run")
        #expect(store.state(for: id2).runConfiguration.command == "make")
    }

    @Test func explicitCommandPreservedOverSuggestion() async {
        let (store, _) = makeStore()
        let id = UUID()
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? "// swift tools".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        let runStore = RunCommandStore(workspaceID: id, rootURL: root, stateStore: store)
        runStore.setCommand("custom", explicit: true)
        await runStore.refreshSuggestion(rootURL: root)

        #expect(runStore.configuration.command == "custom")
        #expect(runStore.configuration.isCommandExplicit)
    }

    @Test func clearingExplicitRestoresSuggestionEligibility() async {
        let (store, _) = makeStore()
        let id = UUID()
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? "// swift".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        let runStore = RunCommandStore(workspaceID: id, rootURL: root, stateStore: store)
        runStore.setCommand("custom", explicit: true)
        runStore.clearExplicitCommand()
        await runStore.refreshSuggestion(rootURL: root)

        #expect(!runStore.configuration.isCommandExplicit)
        #expect(runStore.configuration.command == "swift run")
    }

    @Test func corruptedConfigurationFallback() {
        let suiteName = "com.simplecode.tests.corrupt.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(Data("not json".utf8), forKey: "workspaceState.v1")

        let store = WorkspaceStateStore(defaults: defaults)
        #expect(store.state(for: UUID()).runConfiguration == .default)
    }

    @Test func revealAndClearPreferencesPersist() {
        let (store, _) = makeStore()
        let id = UUID()
        let root = FileManager.default.temporaryDirectory
        let runStore = RunCommandStore(workspaceID: id, rootURL: root, stateStore: store)

        runStore.setRevealTerminalOnRun(false)
        runStore.setClearTerminalBeforeRun(true)

        let reloaded = RunCommandStore(workspaceID: id, rootURL: root, stateStore: store)
        #expect(reloaded.configuration.revealTerminalOnRun == false)
        #expect(reloaded.configuration.clearTerminalBeforeRun == true)
    }

    @Test func legacyTrustFieldsAreIgnoredWhileRunConfigurationSurvives() throws {
        let suiteName = "com.simplecode.tests.legacy-runconfig.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let storageKey = "workspaceState.v1"
        let workspaceID = UUID()
        let legacyPayload: [String: Any] = [
            workspaceID.uuidString: [
                "runConfiguration": [
                    "command": "swift test",
                    "isCommandExplicit": true,
                    "suggestedCommand": NSNull(),
                    "revealTerminalOnRun": false,
                    "clearTerminalBeforeRun": true
                ],
                "trust": "trusted",
                "rootFilesystemIdentity": "legacy-root-identity"
            ]
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: legacyPayload), forKey: storageKey)

        let store = WorkspaceStateStore(defaults: defaults, storageKey: storageKey)
        #expect(store.state(for: workspaceID).runConfiguration.command == "swift test")
        #expect(store.state(for: workspaceID).runConfiguration.isCommandExplicit)
        #expect(store.state(for: workspaceID).runConfiguration.revealTerminalOnRun == false)
        #expect(store.state(for: workspaceID).runConfiguration.clearTerminalBeforeRun)

        store.updateRunConfiguration(for: workspaceID) { $0.command = "swift run" }

        let persistedData = try #require(defaults.data(forKey: storageKey))
        let persistedPayload = try #require(
            JSONSerialization.jsonObject(with: persistedData) as? [String: Any]
        )
        let persistedWorkspace = try #require(
            persistedPayload[workspaceID.uuidString] as? [String: Any]
        )
        #expect(persistedWorkspace["trust"] == nil)
        #expect(persistedWorkspace["rootFilesystemIdentity"] == nil)
    }
}
