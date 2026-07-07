import Foundation

enum SettingsMigration {
    /// Migrates a decoded blob to the current schema, merging unknown future keys safely.
    static func migrate(_ blob: AppSettingsBlob) -> AppSettingsBlob {
        var result = blob
        switch blob.schemaVersion {
        case ..<1:
            result = AppSettingsBlob.defaults
        default:
            result.schemaVersion = AppSettingsBlob.currentSchemaVersion
        }
        result = clamp(result)
        return result
    }

    /// Applies legacy `editor.fontSize.v1` when the new blob is absent.
    static func applyLegacyFontSize(from defaults: UserDefaults, into blob: inout AppSettingsBlob) {
        let legacy = defaults.double(forKey: "editor.fontSize.v1")
        if legacy > 0 {
            blob.typography.editorFontSize = legacy
        }
    }

    private static func clamp(_ blob: AppSettingsBlob) -> AppSettingsBlob {
        var copy = blob
        copy.typography.editorFontFamily = FontCatalog.resolvedMonospacedFamily(copy.typography.editorFontFamily)
        copy.typography.terminalFontFamily = FontCatalog.resolvedMonospacedFamily(copy.typography.terminalFontFamily)
        copy.terminal.fontFamily = FontCatalog.resolvedMonospacedFamily(copy.terminal.fontFamily)
        copy.typography.editorFontSize = clampFinite(
            copy.typography.editorFontSize,
            min: Double(Typography.minimumEditorFontSize),
            max: Double(Typography.maximumEditorFontSize),
            fallback: Double(Typography.defaultEditorFontSize)
        )
        copy.typography.terminalFontSize = clampFinite(
            copy.typography.terminalFontSize,
            min: Double(Typography.minimumEditorFontSize),
            max: Double(Typography.maximumEditorFontSize),
            fallback: Double(Typography.defaultEditorFontSize)
        )
        copy.terminal.fontSize = clampFinite(
            copy.terminal.fontSize,
            min: Double(Typography.minimumEditorFontSize),
            max: Double(Typography.maximumEditorFontSize),
            fallback: Double(Typography.defaultEditorFontSize)
        )
        copy.typography.editorLineHeight = clampFinite(copy.typography.editorLineHeight, min: 1.0, max: 2.5, fallback: 1.2)
        copy.typography.terminalLineSpacing = clampFinite(copy.typography.terminalLineSpacing, min: 0.5, max: 2.5, fallback: 1.0)
        copy.editor.tabWidth = min(max(copy.editor.tabWidth, 1), 16)
        copy.editor.longLineGuideColumn = min(max(copy.editor.longLineGuideColumn, 40), 200)
        copy.files.maximumRecentWorkspaceCount = min(max(copy.files.maximumRecentWorkspaceCount, 1), 50)
        copy.terminal.scrollbackLimit = min(max(copy.terminal.scrollbackLimit, 1_000), 100_000)
        sanitizeColors(in: &copy.appearance)
        sanitizeColors(in: &copy.terminal.background)
        sanitizeColors(in: &copy.terminal.foreground)
        return copy
    }

    private static func clampFinite(_ value: Double, min minimum: Double, max maximum: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return Swift.min(Swift.max(value, minimum), maximum)
    }

    private static func sanitizeColors(in appearance: inout AppearanceSettings) {
        let appearancePairs: [WritableKeyPath<AppearanceSettings, StoredColorPair>] = [
            \.editorBackground,
            \.editorForeground,
            \.editorCurrentLine,
            \.editorSelection,
            \.gutterBackground,
            \.lineNumber,
            \.activeLineNumber,
            \.longLineGuide,
            \.whitespaceMarker,
            \.terminalBackground,
            \.terminalForeground,
        ]
        for keyPath in appearancePairs {
            sanitizeColors(in: &appearance[keyPath: keyPath])
        }

        let palettePairs: [WritableKeyPath<SyntaxPaletteSettings, StoredColorPair>] = [
            \.keyword,
            \.controlFlow,
            \.type,
            \.function,
            \.variable,
            \.string,
            \.number,
            \.comment,
            \.documentationComment,
            \.operator,
            \.punctuation,
            \.preprocessor,
            \.attribute,
            \.label,
            \.constant,
            \.invalid,
            \.plain,
        ]
        for keyPath in palettePairs {
            sanitizeColors(in: &appearance.syntaxPalette[keyPath: keyPath])
        }
    }

    private static func sanitizeColors(in pair: inout StoredColorPair) {
        sanitizeColors(in: &pair.light)
        sanitizeColors(in: &pair.dark)
    }

    private static func sanitizeColors(in color: inout StoredColor) {
        color.red = clampFinite(color.red, min: 0, max: 1, fallback: 0)
        color.green = clampFinite(color.green, min: 0, max: 1, fallback: 0)
        color.blue = clampFinite(color.blue, min: 0, max: 1, fallback: 0)
        color.alpha = clampFinite(color.alpha, min: 0, max: 1, fallback: 1)
    }
}
