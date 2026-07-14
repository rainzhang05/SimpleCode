import Foundation
import CoreGraphics
import AppKit

/// Global application preferences. Owned by `AppModel`, not `WorkspaceModel`.
@MainActor
@Observable
final class AppSettingsStore {
    static let storageKey = "com.simplecode.settings.v1"

    private let defaults: UserDefaults
    private let permitsPersistence: Bool

    private(set) var snapshot: AppSettingsSnapshot {
        didSet { settingsDidChange() }
    }

    var appearance: AppearanceSettings {
        get { snapshot.appearance }
        set { apply(appearance: newValue) }
    }

    var typography: TypographySettings {
        get { snapshot.typography }
        set { apply(typography: newValue) }
    }

    var editor: EditorBehaviorSettings {
        get { snapshot.editor }
        set { apply(editor: newValue) }
    }

    var files: FileDisplaySettings {
        get { snapshot.files }
        set { apply(files: newValue) }
    }

    init(defaults: UserDefaults = .standard) {
        let loaded = Self.load(from: defaults)
        var blob = loaded.blob
        if !loaded.hasPersistedBlob {
            SettingsMigration.applyLegacyFontSize(from: defaults, into: &blob)
        }

        self.defaults = defaults
        self.permitsPersistence = loaded.permitsPersistence
        self.snapshot = AppSettingsSnapshot(
            appearance: blob.appearance,
            typography: blob.typography,
            editor: blob.editor,
            files: blob.files
        )
        applyApplicationAppearance()
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
            apply(appearance: .defaults)
        case .typography:
            apply(typography: .defaults)
        case .editor:
            apply(editor: .defaults)
        case .files:
            apply(files: .defaults)
        }
    }

    func restoreAllDefaults() {
        apply(.defaults)
    }

    private func settingsDidChange() {
        applyApplicationAppearance()
        persist()
    }

    private func applyApplicationAppearance() {
        switch appearance.mode {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func apply(_ snapshot: AppSettingsSnapshot) {
        self.snapshot = snapshot
    }

    private func apply(appearance: AppearanceSettings) {
        apply(AppSettingsSnapshot(
            appearance: appearance,
            typography: snapshot.typography,
            editor: snapshot.editor,
            files: snapshot.files
        ))
    }

    private func apply(typography: TypographySettings) {
        apply(AppSettingsSnapshot(
            appearance: snapshot.appearance,
            typography: typography,
            editor: snapshot.editor,
            files: snapshot.files
        ))
    }

    private func apply(editor: EditorBehaviorSettings) {
        apply(AppSettingsSnapshot(
            appearance: snapshot.appearance,
            typography: snapshot.typography,
            editor: editor,
            files: snapshot.files
        ))
    }

    private func apply(files: FileDisplaySettings) {
        apply(AppSettingsSnapshot(
            appearance: snapshot.appearance,
            typography: snapshot.typography,
            editor: snapshot.editor,
            files: files
        ))
    }

    private func persist() {
        guard permitsPersistence else { return }

        let blob = AppSettingsBlob(
            schemaVersion: AppSettingsBlob.currentSchemaVersion,
            appearance: snapshot.appearance,
            typography: snapshot.typography,
            editor: snapshot.editor,
            files: snapshot.files
        )
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(blob) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private struct LoadedSettings {
        var blob: AppSettingsBlob
        var hasPersistedBlob: Bool
        var permitsPersistence: Bool
    }

    private static func load(from defaults: UserDefaults) -> LoadedSettings {
        guard let data = defaults.data(forKey: storageKey) else {
            return LoadedSettings(
                blob: AppSettingsBlob.defaults,
                hasPersistedBlob: false,
                permitsPersistence: true
            )
        }
        let decoder = JSONDecoder()
        let storedSchemaVersion = try? decoder.decode(PersistedSchemaVersion.self, from: data)
        let isFutureSchema = storedSchemaVersion.map {
            $0.schemaVersion > AppSettingsBlob.currentSchemaVersion
        } ?? false

        guard let mergedData = mergedSettingsData(from: data),
              let blob = try? decoder.decode(AppSettingsBlob.self, from: mergedData) else {
            return LoadedSettings(
                blob: AppSettingsBlob.defaults,
                hasPersistedBlob: true,
                permitsPersistence: !isFutureSchema
            )
        }
        return LoadedSettings(
            blob: SettingsMigration.migrate(blob, legacyData: data),
            hasPersistedBlob: true,
            permitsPersistence: blob.schemaVersion <= AppSettingsBlob.currentSchemaVersion
        )
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

    private struct PersistedSchemaVersion: Decodable {
        let schemaVersion: Int
    }
}
