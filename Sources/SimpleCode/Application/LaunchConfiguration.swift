import Foundation

/// Parsed command-line flags used for automated testing and syntax stress validation.
struct LaunchConfiguration: Sendable, Equatable {
    var openFolderPath: String?
    var useSyntaxStressSample: Bool = false
    var fixtureWorkspacePath: String?
    var fixtureRunWorkspacePath: String?
    var uiTestCloneSource: String?
    var uiTestCloneDestination: String?
    var uiTestUserDefaultsSuite: String?
    var uiTestRunCommand: String?
    var uiTestSeedRecentWorkspacePaths: [String] = []

    static func parse(arguments: [String] = CommandLine.arguments) -> LaunchConfiguration {
        var config = LaunchConfiguration()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "-UITestOpenFolder", "-UITestFixtureWorkspace":
                if index + 1 < arguments.count {
                    config.openFolderPath = arguments[index + 1]
                    if argument == "-UITestFixtureWorkspace" {
                        config.fixtureWorkspacePath = arguments[index + 1]
                    }
                    index += 1
                }
            case "-UITestFixtureRunWorkspace":
                if index + 1 < arguments.count {
                    config.fixtureRunWorkspacePath = arguments[index + 1]
                    config.openFolderPath = arguments[index + 1]
                    index += 1
                }
            case "-UITestCloneSource":
                if index + 1 < arguments.count {
                    config.uiTestCloneSource = arguments[index + 1]
                    index += 1
                }
            case "-UITestCloneDestination":
                if index + 1 < arguments.count {
                    config.uiTestCloneDestination = arguments[index + 1]
                    index += 1
                }
            case "-UITestRunCommand":
                if index + 1 < arguments.count {
                    config.uiTestRunCommand = arguments[index + 1]
                    index += 1
                }
            case "-UITestSeedRecentWorkspace":
                if index + 1 < arguments.count {
                    config.uiTestSeedRecentWorkspacePaths.append(arguments[index + 1])
                    index += 1
                }
            case "-UITestUserDefaultsSuite":
                if index + 1 < arguments.count {
                    config.uiTestUserDefaultsSuite = arguments[index + 1]
                    index += 1
                }
            case "-SyntaxStressTest":
                config.useSyntaxStressSample = true
            default:
                break
            }
            index += 1
        }
        if config.uiTestUserDefaultsSuite == nil,
           let suite = ProcessInfo.processInfo.environment["SIMPLECODE_UI_TEST_DEFAULTS_SUITE"] {
            config.uiTestUserDefaultsSuite = suite
        }
        return config
    }
}
