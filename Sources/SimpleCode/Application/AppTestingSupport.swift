import Foundation

enum AppTestingSupport {
    static func isUITesting(launchConfiguration: LaunchConfiguration) -> Bool {
        ProcessInfo.processInfo.environment["SIMPLECODE_UI_TESTING"] == "1"
            || launchConfiguration.uiTestUserDefaultsSuite != nil
    }

    static func makeUserDefaults(launchConfiguration: LaunchConfiguration) -> UserDefaults {
        if let suite = launchConfiguration.uiTestUserDefaultsSuite,
           let defaults = UserDefaults(suiteName: suite) {
            return defaults
        }
        return .standard
    }
}
