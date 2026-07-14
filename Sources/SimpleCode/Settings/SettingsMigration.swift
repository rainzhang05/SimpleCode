import Foundation

enum SettingsMigration {
    /// Migrates a decoded blob to the current schema while retaining only
    /// functional preferences supported by schema v4.
    static func migrate(_ blob: AppSettingsBlob, legacyData: Data? = nil) -> AppSettingsBlob {
        guard blob.schemaVersion >= 1 else {
            return AppSettingsBlob.defaults
        }

        // A newer app may have written fields this version does not understand.
        // Expose compatible values without allowing this app to overwrite them.
        guard blob.schemaVersion <= AppSettingsBlob.currentSchemaVersion else {
            return clamp(blob)
        }

        var result = blob
        if blob.schemaVersion == 1 {
            migrateVersionOneTerminalTypography(in: &result, legacyData: legacyData)
        }
        if blob.schemaVersion < 4 {
            result.appearance = .defaults
        }
        result.schemaVersion = AppSettingsBlob.currentSchemaVersion
        return clamp(result)
    }

    /// Applies legacy `editor.fontSize.v1` when the settings blob is absent.
    static func applyLegacyFontSize(from defaults: UserDefaults, into blob: inout AppSettingsBlob) {
        let legacy = defaults.double(forKey: "editor.fontSize.v1")
        if legacy > 0 {
            blob.typography.editorFontSize = legacy
        }
    }

    private static func migrateVersionOneTerminalTypography(
        in blob: inout AppSettingsBlob,
        legacyData: Data?
    ) {
        let legacyTerminal = legacyData
            .flatMap { try? JSONDecoder().decode(VersionOneCompatibility.self, from: $0) }
            .flatMap(\.terminal)

        if blob.typography.terminalFontFamily == TypographySettings.defaults.terminalFontFamily,
           let fontFamily = legacyTerminal?.fontFamily,
           fontFamily != Typography.systemMonospacedFamilyName {
            blob.typography.terminalFontFamily = fontFamily
        }
        if blob.typography.terminalFontSize == Double(Typography.defaultEditorFontSize),
           let fontSize = legacyTerminal?.fontSize,
           fontSize != Double(Typography.defaultEditorFontSize) {
            blob.typography.terminalFontSize = fontSize
        }
    }

    private static func clamp(_ blob: AppSettingsBlob) -> AppSettingsBlob {
        var copy = blob
        copy.typography.editorFontFamily = FontCatalog.resolvedMonospacedFamily(copy.typography.editorFontFamily)
        copy.typography.terminalFontFamily = FontCatalog.resolvedMonospacedFamily(copy.typography.terminalFontFamily)
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
        copy.editor.tabWidth = min(max(copy.editor.tabWidth, 1), 16)
        copy.editor.longLineGuideColumn = min(max(copy.editor.longLineGuideColumn, 40), 200)
        return copy
    }

    private static func clampFinite(
        _ value: Double,
        min minimum: Double,
        max maximum: Double,
        fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return Swift.min(Swift.max(value, minimum), maximum)
    }
}

private struct VersionOneCompatibility: Decodable {
    struct Terminal: Decodable {
        var fontFamily: String?
        var fontSize: Double?
    }

    var terminal: Terminal?
}
