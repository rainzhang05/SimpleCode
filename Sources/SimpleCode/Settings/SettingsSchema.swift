import Foundation

enum SettingsSection: String, CaseIterable, Sendable {
    case appearance
    case typography
    case editor
    case files
}

/// Versioned root settings blob persisted under the stable legacy storage key.
struct AppSettingsBlob: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 3

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

struct AppearanceSettings: Codable, Equatable, Sendable {
    var editorBackground: StoredColorPair
    var editorForeground: StoredColorPair
    var editorCurrentLine: StoredColorPair
    var editorSelection: StoredColorPair
    var gutterBackground: StoredColorPair
    var lineNumber: StoredColorPair
    var activeLineNumber: StoredColorPair
    var longLineGuide: StoredColorPair
    var whitespaceMarker: StoredColorPair
    var terminalBackground: StoredColorPair
    var terminalForeground: StoredColorPair
    var syntaxPalette: SyntaxPaletteSettings

    static var defaults: AppearanceSettings {
        AppearanceSettings(
            editorBackground: StoredColorPair(pair: ColorRoleDefaults.editorBackground),
            editorForeground: StoredColorPair(pair: ColorRoleDefaults.editorForeground),
            editorCurrentLine: StoredColorPair(pair: ColorRoleDefaults.editorCurrentLine),
            editorSelection: StoredColorPair(pair: ColorRoleDefaults.editorSelection),
            gutterBackground: StoredColorPair(pair: ColorRoleDefaults.gutterBackground),
            lineNumber: StoredColorPair(pair: ColorRoleDefaults.lineNumber),
            activeLineNumber: StoredColorPair(pair: ColorRoleDefaults.activeLineNumber),
            longLineGuide: StoredColorPair(pair: ColorRoleDefaults.longLineGuide),
            whitespaceMarker: StoredColorPair(pair: ColorRoleDefaults.whitespaceMarker),
            terminalBackground: StoredColorPair(pair: ColorRoleDefaults.terminalBackground),
            terminalForeground: StoredColorPair(pair: ColorRoleDefaults.terminalForeground),
            syntaxPalette: .defaults
        )
    }
}

struct SyntaxPaletteSettings: Codable, Equatable, Sendable {
    var keyword: StoredColorPair
    var controlFlow: StoredColorPair
    var type: StoredColorPair
    var function: StoredColorPair
    var variable: StoredColorPair
    var string: StoredColorPair
    var number: StoredColorPair
    var comment: StoredColorPair
    var documentationComment: StoredColorPair
    var `operator`: StoredColorPair
    var punctuation: StoredColorPair
    var preprocessor: StoredColorPair
    var attribute: StoredColorPair
    var label: StoredColorPair
    var constant: StoredColorPair
    var invalid: StoredColorPair
    var plain: StoredColorPair

    static var defaults: SyntaxPaletteSettings {
        SyntaxPaletteSettings(
            keyword: StoredColorPair(pair: SyntaxPaletteDefaults.keyword),
            controlFlow: StoredColorPair(pair: SyntaxPaletteDefaults.controlFlow),
            type: StoredColorPair(pair: SyntaxPaletteDefaults.type),
            function: StoredColorPair(pair: SyntaxPaletteDefaults.function),
            variable: StoredColorPair(pair: SyntaxPaletteDefaults.variable),
            string: StoredColorPair(pair: SyntaxPaletteDefaults.string),
            number: StoredColorPair(pair: SyntaxPaletteDefaults.number),
            comment: StoredColorPair(pair: SyntaxPaletteDefaults.comment),
            documentationComment: StoredColorPair(pair: SyntaxPaletteDefaults.documentationComment),
            operator: StoredColorPair(pair: SyntaxPaletteDefaults.operator),
            punctuation: StoredColorPair(pair: SyntaxPaletteDefaults.punctuation),
            preprocessor: StoredColorPair(pair: SyntaxPaletteDefaults.preprocessor),
            attribute: StoredColorPair(pair: SyntaxPaletteDefaults.attribute),
            label: StoredColorPair(pair: SyntaxPaletteDefaults.label),
            constant: StoredColorPair(pair: SyntaxPaletteDefaults.constant),
            invalid: StoredColorPair(pair: SyntaxPaletteDefaults.invalid),
            plain: StoredColorPair(pair: SyntaxPaletteDefaults.plain)
        )
    }

    func pair(for category: SyntaxCategory) -> StoredColorPair {
        switch category {
        case .keyword: keyword
        case .controlFlow: controlFlow
        case .type: type
        case .function: function
        case .variable: variable
        case .string: string
        case .number: number
        case .comment: comment
        case .documentationComment: documentationComment
        case .operator: `operator`
        case .punctuation: punctuation
        case .preprocessor: preprocessor
        case .attribute: attribute
        case .label: label
        case .constant: constant
        case .invalid: invalid
        case .plain: plain
        case .operatorOrPunctuation: `operator`
        }
    }
}

// MARK: - Typography

struct TypographySettings: Codable, Equatable, Sendable {
    var editorFontFamily: String
    var editorFontSize: Double
    var editorLineHeight: Double
    var editorFontLigatures: Bool
    var terminalFontFamily: String
    var terminalFontSize: Double

    static var defaults: TypographySettings {
        TypographySettings(
            editorFontFamily: Typography.systemMonospacedFamilyName,
            editorFontSize: Double(Typography.defaultEditorFontSize),
            editorLineHeight: 1.2,
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
