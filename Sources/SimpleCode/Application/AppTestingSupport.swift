import Foundation

enum AppTestingSupport {
    static func isUITesting(launchConfiguration: LaunchConfiguration) -> Bool {
        ProcessInfo.processInfo.environment["SIMPLECODE_UI_TESTING"] == "1"
            || launchConfiguration.uiTestUserDefaultsSuite != nil
    }

    static func makeUserDefaults(launchConfiguration: LaunchConfiguration) -> UserDefaults {
        if isUITesting(launchConfiguration: launchConfiguration) {
            return EphemeralUserDefaults()
        }
        return .standard
    }
}

final class EphemeralUserDefaults: UserDefaults {
    private var storage: [String: Any] = [:]

    init() {
        super.init(suiteName: "com.simplecode.ephemeral.\(UUID().uuidString)")!
    }

    override func object(forKey defaultName: String) -> Any? {
        storage[defaultName]
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value
    }

    override func removeObject(forKey defaultName: String) {
        storage.removeValue(forKey: defaultName)
    }

    override func data(forKey defaultName: String) -> Data? {
        storage[defaultName] as? Data
    }

    override func string(forKey defaultName: String) -> String? {
        storage[defaultName] as? String
    }

    override func double(forKey defaultName: String) -> Double {
        if let value = storage[defaultName] as? Double { return value }
        if let value = storage[defaultName] as? NSNumber { return value.doubleValue }
        return 0
    }

    override func integer(forKey defaultName: String) -> Int {
        if let value = storage[defaultName] as? Int { return value }
        if let value = storage[defaultName] as? NSNumber { return value.intValue }
        return 0
    }

    override func bool(forKey defaultName: String) -> Bool {
        if let value = storage[defaultName] as? Bool { return value }
        if let value = storage[defaultName] as? NSNumber { return value.boolValue }
        return false
    }

    override func dictionaryRepresentation() -> [String: Any] {
        storage
    }

    override func removePersistentDomain(forName domainName: String) {
        storage.removeAll()
    }

    override func synchronize() -> Bool {
        true
    }
}
