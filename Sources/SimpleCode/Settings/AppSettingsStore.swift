import Foundation
import CoreGraphics

/// Global application preferences. Owned by `AppModel`, not `WorkspaceModel`.
@MainActor
@Observable
final class AppSettingsStore {
    static let storageKey = "com.simplecode.settings.v1"

    private let defaults: UserDefaults
    private(set) var revision: Int = 0

    var appearance: AppearanceSettings { didSet { SettingsColorResolver.updateSnapshot(appearance); persist() } }
    var typography: TypographySettings { didSet { persist() } }
    var editor: EditorBehaviorSettings { didSet { persist() } }
    var files: FileDisplaySettings { didSet { persist() } }
    var terminal: TerminalAppearanceSettings { didSet { persist() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var blob = Self.load(from: defaults)
        SettingsMigration.applyLegacyFontSize(from: defaults, into: &blob)
        self.appearance = blob.appearance
        self.typography = blob.typography
        self.editor = blob.editor
        self.files = blob.files
        self.terminal = blob.terminal
        SettingsColorResolver.updateSnapshot(blob.appearance)
    }

    var editorFontSize: CGFloat {
        get { CGFloat(typography.editorFontSize) }
        set { typography.editorFontSize = Double(newValue) }
    }

    func increaseFontSize() {
        editorFontSize = min(editorFontSize + 1, Typography.maximumEditorFontSize)
    }

    func decreaseFontSize() {
        editorFontSize = max(editorFontSize - 1, Typography.minimumEditorFontSize)
    }

    func restoreDefaults(for section: SettingsSection) {
        switch section {
        case .appearance:
            appearance = .defaults
            SettingsColorResolver.updateSnapshot(appearance)
        case .typography:
            typography = .defaults
        case .editor:
            editor = .defaults
        case .files:
            files = .defaults
        case .terminal:
            terminal = .defaults
        }
        bumpRevision()
    }

    func restoreAllDefaults() {
        let blob = AppSettingsBlob.defaults
        appearance = blob.appearance
        typography = blob.typography
        editor = blob.editor
        files = blob.files
        terminal = blob.terminal
        SettingsColorResolver.updateSnapshot(appearance)
        bumpRevision()
    }

    func resetSyntaxPalette() {
        appearance.syntaxPalette = .defaults
        SettingsColorResolver.updateSnapshot(appearance)
        bumpRevision()
    }

    func bumpRevision() {
        revision += 1
    }

    private func persist() {
        let blob = AppSettingsBlob(
            schemaVersion: AppSettingsBlob.currentSchemaVersion,
            appearance: appearance,
            typography: typography,
            editor: editor,
            files: files,
            terminal: terminal
        )
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(blob) {
            defaults.set(data, forKey: Self.storageKey)
        }
        bumpRevision()
    }

    private static func load(from defaults: UserDefaults) -> AppSettingsBlob {
        guard let data = defaults.data(forKey: storageKey) else {
            return AppSettingsBlob.defaults
        }
        let decoder = JSONDecoder()

        guard let mergedData = mergedSettingsData(from: data),
              let blob = try? decoder.decode(AppSettingsBlob.self, from: mergedData) else {
            return AppSettingsBlob.defaults
        }
        return SettingsMigration.migrate(blob)
    }

    private static func mergedSettingsData(from data: Data) -> Data? {
        let encoder = JSONEncoder()
        guard let defaultData = try? encoder.encode(AppSettingsBlob.defaults),
              let defaultObject = try? JSONSerialization.jsonObject(with: defaultData) as? [String: Any],
              let incomingObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let merged = merge(defaultObject: defaultObject, incomingObject: incomingObject)
        return try? JSONSerialization.data(withJSONObject: merged)
    }

    private static func merge(defaultObject: [String: Any], incomingObject: [String: Any]) -> [String: Any] {
        var merged: [String: Any] = [:]
        for (key, defaultValue) in defaultObject {
            merged[key] = mergedValue(defaultValue: defaultValue, incomingValue: incomingObject[key])
        }
        return merged
    }

    private static func mergedValue(defaultValue: Any, incomingValue: Any?) -> Any {
        guard let incomingValue else { return defaultValue }

        if let defaultDictionary = defaultValue as? [String: Any],
           let incomingDictionary = incomingValue as? [String: Any] {
            return merge(defaultObject: defaultDictionary, incomingObject: incomingDictionary)
        }

        if defaultValue is [Any] {
            return incomingValue is [Any] ? incomingValue : defaultValue
        }

        if isJSONBool(defaultValue) {
            return isJSONBool(incomingValue) ? incomingValue : defaultValue
        }

        if defaultValue is NSNumber {
            return incomingValue is NSNumber && !isJSONBool(incomingValue) ? incomingValue : defaultValue
        }

        if defaultValue is String {
            return incomingValue is String ? incomingValue : defaultValue
        }

        return incomingValue
    }

    private static func isJSONBool(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}
