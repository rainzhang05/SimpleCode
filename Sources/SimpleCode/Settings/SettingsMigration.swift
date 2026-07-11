import Foundation

enum SettingsMigration {
    /// Migrates a decoded blob to the current schema, merging unknown future keys safely.
    static func migrate(_ blob: AppSettingsBlob) -> AppSettingsBlob {
        guard blob.schemaVersion >= 1 else {
            return AppSettingsBlob.defaults
        }

        // Keep the version intact for a blob written by a newer app. The store
        // will expose the compatible fields, but must not overwrite unknown data.
        guard blob.schemaVersion <= AppSettingsBlob.currentSchemaVersion else {
            return clamp(blob)
        }

        var result = blob
        if blob.schemaVersion == 1 {
            result = migrateVersionOne(result)
        }
        result.schemaVersion = AppSettingsBlob.currentSchemaVersion
        return clamp(result)
    }

    /// Applies legacy `editor.fontSize.v1` when the new blob is absent.
    static func applyLegacyFontSize(from defaults: UserDefaults, into blob: inout AppSettingsBlob) {
        let legacy = defaults.double(forKey: "editor.fontSize.v1")
        if legacy > 0 {
            blob.typography.editorFontSize = legacy
        }
    }

    private static func migrateVersionOne(_ blob: AppSettingsBlob) -> AppSettingsBlob {
        var result = blob

        // v1 exposed terminal typography and colors twice. A deliberate value
        // in the old Terminal pane wins only when the dedicated v1 counterpart
        // is still its default, so a newer explicit choice is never discarded.
        if result.typography.terminalFontFamily == TypographySettings.defaults.terminalFontFamily,
           result.terminal.fontFamily != VersionOneDefaults.terminalFontFamily {
            result.typography.terminalFontFamily = result.terminal.fontFamily
        }
        if result.typography.terminalFontSize == VersionOneDefaults.terminalFontSize,
           result.terminal.fontSize != VersionOneDefaults.terminalFontSize {
            result.typography.terminalFontSize = result.terminal.fontSize
        }
        if result.appearance.terminalBackground == VersionOneDefaults.terminalBackground,
           result.terminal.background != VersionOneDefaults.terminalBackground {
            result.appearance.terminalBackground = result.terminal.background
        }
        if result.appearance.terminalForeground == VersionOneDefaults.terminalForeground,
           result.terminal.foreground != VersionOneDefaults.terminalForeground {
            result.appearance.terminalForeground = result.terminal.foreground
        }

        migrateVersionOnePaletteDefaults(in: &result.appearance)
        result.files.showHiddenFiles = true
        return result
    }

    private static func migrateVersionOnePaletteDefaults(in appearance: inout AppearanceSettings) {
        let current = AppearanceSettings.defaults
        replaceVersionOneDefault(&appearance.editorBackground, with: current.editorBackground, legacy: VersionOneDefaults.editorBackground)
        replaceVersionOneDefault(&appearance.editorForeground, with: current.editorForeground, legacy: VersionOneDefaults.editorForeground)
        replaceVersionOneDefault(&appearance.editorCurrentLine, with: current.editorCurrentLine, legacy: VersionOneDefaults.editorCurrentLine)
        replaceVersionOneDefault(&appearance.editorSelection, with: current.editorSelection, legacy: VersionOneDefaults.editorSelection)
        replaceVersionOneDefault(&appearance.gutterBackground, with: current.gutterBackground, legacy: VersionOneDefaults.gutterBackground)
        replaceVersionOneDefault(&appearance.lineNumber, with: current.lineNumber, legacy: VersionOneDefaults.lineNumber)
        replaceVersionOneDefault(&appearance.activeLineNumber, with: current.activeLineNumber, legacy: VersionOneDefaults.activeLineNumber)
        replaceVersionOneDefault(&appearance.longLineGuide, with: current.longLineGuide, legacy: VersionOneDefaults.longLineGuide)
        replaceVersionOneDefault(&appearance.whitespaceMarker, with: current.whitespaceMarker, legacy: VersionOneDefaults.whitespaceMarker)
        replaceVersionOneDefault(&appearance.terminalBackground, with: current.terminalBackground, legacy: VersionOneDefaults.terminalBackground)
        replaceVersionOneDefault(&appearance.terminalForeground, with: current.terminalForeground, legacy: VersionOneDefaults.terminalForeground)
    }

    private static func replaceVersionOneDefault(
        _ value: inout StoredColorPair,
        with current: StoredColorPair,
        legacy: StoredColorPair
    ) {
        if value == legacy {
            value = current
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

private enum VersionOneDefaults {
    static let terminalFontFamily = Typography.systemMonospacedFamilyName
    static let terminalFontSize = Double(Typography.defaultEditorFontSize)

    static let editorBackground = pair(light: (0.99, 0.99, 0.99, 1), dark: (0.11, 0.11, 0.12, 1))
    static let editorForeground = pair(light: (0.09, 0.09, 0.10, 1), dark: (0.92, 0.93, 0.94, 1))
    static let editorCurrentLine = pair(light: (0, 0, 0, 0.045), dark: (1, 1, 1, 0.06))
    static let editorSelection = pair(light: (0.20, 0.47, 0.95, 0.22), dark: (0.28, 0.55, 1, 0.30))
    static let gutterBackground = pair(light: (0.97, 0.97, 0.97, 1), dark: (0.09, 0.09, 0.10, 1))
    static let lineNumber = pair(light: (0.55, 0.55, 0.58, 1), dark: (0.50, 0.51, 0.55, 1))
    static let activeLineNumber = pair(light: (0.20, 0.20, 0.22, 1), dark: (0.88, 0.89, 0.91, 1))
    static let longLineGuide = pair(light: (0, 0, 0, 0.08), dark: (1, 1, 1, 0.10))
    static let whitespaceMarker = pair(light: (0, 0, 0, 0.18), dark: (1, 1, 1, 0.20))
    static let terminalBackground = pair(light: (0.98, 0.98, 0.98, 1), dark: (0.08, 0.08, 0.09, 1))
    static let terminalForeground = pair(light: (0.10, 0.10, 0.10, 1), dark: (0.90, 0.90, 0.90, 1))

    private static func pair(
        light: (Double, Double, Double, Double),
        dark: (Double, Double, Double, Double)
    ) -> StoredColorPair {
        StoredColorPair(
            light: StoredColor(red: light.0, green: light.1, blue: light.2, alpha: light.3),
            dark: StoredColor(red: dark.0, green: dark.1, blue: dark.2, alpha: dark.3)
        )
    }
}
