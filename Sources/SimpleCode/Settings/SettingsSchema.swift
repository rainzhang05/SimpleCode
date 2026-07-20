import Foundation

enum SettingsSection: String, CaseIterable, Sendable {
    case appearance
    case typography
    case editor
    case files
}

/// Versioned root settings blob persisted under the stable legacy storage key.
struct AppSettingsBlob: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 4

    var schemaVersion: Int
    var appearance: AppearanceSettings
    var typography: TypographySettings
    var editor: EditorBehaviorSettings
    var files: FileDisplaySettings

    static var defaults: AppSettingsBlob {
        AppSettingsBlob(
            schemaVersion: currentSchemaVersion,
            appearance: .defaults,
            typography: .defaults,
            editor: .defaults,
            files: .defaults
        )
    }
}

/// Immutable value passed to runtime consumers so a render or native-view
/// update observes one coherent settings generation.
struct AppSettingsSnapshot: Equatable, Sendable {
    let appearance: AppearanceSettings
    let typography: TypographySettings
    let editor: EditorBehaviorSettings
    let files: FileDisplaySettings

    static let defaults = AppSettingsSnapshot(
        appearance: .defaults,
        typography: .defaults,
        editor: .defaults,
        files: .defaults
    )
}

// MARK: - Appearance

enum AppAppearanceMode: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark
}

struct AppearanceSettings: Codable, Equatable, Sendable {
    var mode: AppAppearanceMode

    static var defaults: AppearanceSettings {
        AppearanceSettings(mode: .system)
    }
}

// MARK: - Typography

struct TypographySettings: Codable, Equatable, Sendable {
    var editorFontFamily: String
    var editorFontSize: Double
    var editorFontLigatures: Bool
    var terminalFontFamily: String
    var terminalFontSize: Double

    static var defaults: TypographySettings {
        TypographySettings(
            editorFontFamily: Typography.defaultEditorFontFamily,
            editorFontSize: Double(Typography.defaultEditorFontSize),
            editorFontLigatures: false,
            terminalFontFamily: Typography.systemMonospacedFamilyName,
            terminalFontSize: Double(Typography.defaultEditorFontSize)
        )
    }
}

// MARK: - Editor behavior

struct EditorBehaviorSettings: Codable, Equatable, Sendable {
    var tabWidth: Int
    var insertSpaces: Bool
    var autoIndent: Bool
    var autoClosingPairs: Bool
    var smartPairDeletion: Bool
    var smartHome: Bool
    var smartBackspace: Bool
    var wordWrap: Bool
    var showLineNumbers: Bool
    var highlightCurrentLine: Bool
    var showWhitespace: Bool
    var showTrailingWhitespace: Bool
    var showLongLineGuide: Bool
    var longLineGuideColumn: Int
    var trimTrailingWhitespaceOnSave: Bool
    var ensureFinalNewlineOnSave: Bool

    static var defaults: EditorBehaviorSettings {
        EditorBehaviorSettings(
            tabWidth: 4,
            insertSpaces: true,
            autoIndent: true,
            autoClosingPairs: true,
            smartPairDeletion: true,
            smartHome: true,
            smartBackspace: true,
            wordWrap: false,
            showLineNumbers: true,
            highlightCurrentLine: true,
            showWhitespace: false,
            showTrailingWhitespace: false,
            showLongLineGuide: true,
            longLineGuideColumn: 100,
            trimTrailingWhitespaceOnSave: false,
            ensureFinalNewlineOnSave: true
        )
    }
}

// MARK: - Files

struct FileDisplaySettings: Codable, Equatable, Sendable {
    var userExclusions: [String]

    static var defaults: FileDisplaySettings {
        FileDisplaySettings(
            userExclusions: []
        )
    }
}
