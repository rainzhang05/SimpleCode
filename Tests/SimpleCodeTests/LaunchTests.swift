import Foundation
import Testing
@testable import SimpleCode

struct LaunchConfigurationTests {
    @Test func parsesOpenFolderLaunchArgument() {
        let config = LaunchConfiguration.parse(arguments: ["SimpleCode", "-UITestOpenFolder", "/tmp/project"])

        #expect(config.openFolderPath == "/tmp/project")
        #expect(!config.useSyntaxStressSample)
    }

    @Test func parsesSyntaxStressLaunchArgument() {
        let config = LaunchConfiguration.parse(arguments: ["SimpleCode", "-SyntaxStressTest"])

        #expect(config.useSyntaxStressSample)
        #expect(config.openFolderPath == nil)
    }
}

@Suite(.serialized)
@MainActor
struct LaunchIntegrationTests {
    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "com.simplecode.tests.launch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SimpleCodeLaunchTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func launchArgumentOpensWorkspaceDirectly() throws {
        let folder = try makeTemporaryDirectory()
        let defaults = makeIsolatedDefaults()
        let config = LaunchConfiguration(openFolderPath: folder.path, useSyntaxStressSample: false)
        let appModel = AppModel(
            recentWorkspaces: RecentWorkspaceStore(defaults: defaults),
            editorSettings: AppSettingsStore(defaults: defaults),
            launchConfiguration: config
        )

        #expect(appModel.isWorkspaceOpen)
        switch appModel.route {
        case .workspace(let workspace):
            #expect(workspace.rootURL.standardizedFileURL.path == folder.standardizedFileURL.path)
        case .welcome:
            Issue.record("Expected workspace route from launch configuration")
        }
    }

    @Test func syntaxStressFlagLoadsLargeSampleInWorkspace() throws {
        let folder = try makeTemporaryDirectory()
        let defaults = makeIsolatedDefaults()
        let config = LaunchConfiguration(openFolderPath: folder.path, useSyntaxStressSample: true)
        let appModel = AppModel(
            recentWorkspaces: RecentWorkspaceStore(defaults: defaults),
            editorSettings: AppSettingsStore(defaults: defaults),
            launchConfiguration: config
        )

        guard case .workspace(let workspace) = appModel.route else {
            Issue.record("Expected workspace route")
            return
        }
        #expect(workspace.useSyntaxStressSample)
    }
}
