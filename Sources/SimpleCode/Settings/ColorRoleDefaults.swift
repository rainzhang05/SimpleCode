import AppKit

/// Built-in default color pairs used before settings load and for restore-defaults.
enum ColorRoleDefaults {
    static let editorBackground = ColorRolePair(
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        dark: NSColor(srgbRed: 11.0 / 255, green: 12.0 / 255, blue: 14.0 / 255, alpha: 1)
    )
    static let editorForeground = ColorRolePair(
        light: NSColor(srgbRed: 21.0 / 255, green: 23.0 / 255, blue: 26.0 / 255, alpha: 1),
        dark: NSColor(srgbRed: 245.0 / 255, green: 247.0 / 255, blue: 250.0 / 255, alpha: 1)
    )
    static let editorCurrentLine = ColorRolePair(
        light: NSColor(srgbRed: 0, green: 122.0 / 255, blue: 1, alpha: 0.055),
        dark: NSColor(srgbRed: 10.0 / 255, green: 132.0 / 255, blue: 1, alpha: 0.10)
    )
    static let editorSelection = ColorRolePair(
        light: NSColor(srgbRed: 0, green: 122.0 / 255, blue: 1, alpha: 0.22),
        dark: NSColor(srgbRed: 10.0 / 255, green: 132.0 / 255, blue: 1, alpha: 0.30)
    )
    static let gutterBackground = ColorRolePair(
        light: NSColor(srgbRed: 248.0 / 255, green: 249.0 / 255, blue: 250.0 / 255, alpha: 1),
        dark: NSColor(srgbRed: 17.0 / 255, green: 19.0 / 255, blue: 23.0 / 255, alpha: 1)
    )
    static let lineNumber = ColorRolePair(
        light: NSColor(srgbRed: 107.0 / 255, green: 114.0 / 255, blue: 128.0 / 255, alpha: 1),
        dark: NSColor(srgbRed: 139.0 / 255, green: 148.0 / 255, blue: 158.0 / 255, alpha: 1)
    )
    static let activeLineNumber = ColorRolePair(
        light: NSColor(srgbRed: 21.0 / 255, green: 23.0 / 255, blue: 26.0 / 255, alpha: 1),
        dark: NSColor(srgbRed: 245.0 / 255, green: 247.0 / 255, blue: 250.0 / 255, alpha: 1)
    )
    static let longLineGuide = ColorRolePair(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.08),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10)
    )
    static let whitespaceMarker = ColorRolePair(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.18),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.20)
    )
    static let terminalBackground = ColorRolePair(
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        dark: NSColor(srgbRed: 11.0 / 255, green: 12.0 / 255, blue: 14.0 / 255, alpha: 1)
    )
    static let terminalForeground = ColorRolePair(
        light: NSColor(srgbRed: 21.0 / 255, green: 23.0 / 255, blue: 26.0 / 255, alpha: 1),
        dark: NSColor(srgbRed: 245.0 / 255, green: 247.0 / 255, blue: 250.0 / 255, alpha: 1)
    )
}

/// Exact schema-v2 violet defaults retained solely for value-based migration.
/// A future migration can replace these pairs without treating a user's custom
/// purple as an app default.
enum LegacyVioletColorRoleDefaults {
    static let editorBackground = ColorRolePair(
        light: NSColor(srgbRed: 1, green: 0.988, blue: 1, alpha: 1),
        dark: NSColor(srgbRed: 0.090, green: 0.078, blue: 0.129, alpha: 1)
    )
    static let editorForeground = ColorRolePair(
        light: NSColor(srgbRed: 0.114, green: 0.094, blue: 0.188, alpha: 1),
        dark: NSColor(srgbRed: 0.957, green: 0.941, blue: 1, alpha: 1)
    )
    static let editorCurrentLine = ColorRolePair(
        light: NSColor(srgbRed: 0.404, green: 0.341, blue: 0.914, alpha: 0.075),
        dark: NSColor(srgbRed: 0.706, green: 0.659, blue: 1, alpha: 0.14)
    )
    static let editorSelection = ColorRolePair(
        light: NSColor(srgbRed: 0.404, green: 0.341, blue: 0.914, alpha: 0.24),
        dark: NSColor(srgbRed: 0.706, green: 0.659, blue: 1, alpha: 0.36)
    )
    static let gutterBackground = ColorRolePair(
        light: NSColor(srgbRed: 0.961, green: 0.945, blue: 1, alpha: 1),
        dark: NSColor(srgbRed: 0.125, green: 0.106, blue: 0.173, alpha: 1)
    )
    static let lineNumber = ColorRolePair(
        light: NSColor(srgbRed: 0.400, green: 0.365, blue: 0.490, alpha: 1),
        dark: NSColor(srgbRed: 0.690, green: 0.647, blue: 0.780, alpha: 1)
    )
    static let activeLineNumber = ColorRolePair(
        light: NSColor(srgbRed: 0.231, green: 0.192, blue: 0.341, alpha: 1),
        dark: NSColor(srgbRed: 0.925, green: 0.898, blue: 1, alpha: 1)
    )
    static let longLineGuide = ColorRolePair(
        light: NSColor(srgbRed: 0.404, green: 0.341, blue: 0.914, alpha: 0.22),
        dark: NSColor(srgbRed: 0.706, green: 0.659, blue: 1, alpha: 0.32)
    )
    static let whitespaceMarker = ColorRolePair(
        light: NSColor(srgbRed: 0.424, green: 0.365, blue: 0.600, alpha: 0.34),
        dark: NSColor(srgbRed: 0.710, green: 0.659, blue: 0.835, alpha: 0.38)
    )
    static let terminalBackground = ColorRolePair(
        light: NSColor(srgbRed: 0.090, green: 0.067, blue: 0.157, alpha: 1),
        dark: NSColor(srgbRed: 0.055, green: 0.039, blue: 0.094, alpha: 1)
    )
    static let terminalForeground = ColorRolePair(
        light: NSColor(srgbRed: 0.965, green: 0.941, blue: 1, alpha: 1),
        dark: NSColor(srgbRed: 0.965, green: 0.941, blue: 1, alpha: 1)
    )
}

enum SyntaxPaletteDefaults {
    static let keyword = ColorRolePair(
        light: NSColor(srgbRed: 0.64, green: 0.11, blue: 0.51, alpha: 1),
        dark: NSColor(srgbRed: 0.98, green: 0.47, blue: 0.75, alpha: 1)
    )
    static let controlFlow = ColorRolePair(
        light: NSColor(srgbRed: 0.64, green: 0.11, blue: 0.51, alpha: 1),
        dark: NSColor(srgbRed: 0.98, green: 0.47, blue: 0.75, alpha: 1)
    )
    static let type = ColorRolePair(
        light: NSColor(srgbRed: 0.11, green: 0.42, blue: 0.55, alpha: 1),
        dark: NSColor(srgbRed: 0.45, green: 0.80, blue: 0.86, alpha: 1)
    )
    static let function = ColorRolePair(
        light: NSColor(srgbRed: 0.24, green: 0.29, blue: 0.64, alpha: 1),
        dark: NSColor(srgbRed: 0.62, green: 0.67, blue: 0.98, alpha: 1)
    )
    static let variable = ColorRolePair(
        light: NSColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 1),
        dark: NSColor(srgbRed: 0.90, green: 0.91, blue: 0.92, alpha: 1)
    )
    static let string = ColorRolePair(
        light: NSColor(srgbRed: 0.77, green: 0.10, blue: 0.09, alpha: 1),
        dark: NSColor(srgbRed: 0.98, green: 0.55, blue: 0.48, alpha: 1)
    )
    static let number = ColorRolePair(
        light: NSColor(srgbRed: 0.11, green: 0.44, blue: 0.25, alpha: 1),
        dark: NSColor(srgbRed: 0.60, green: 0.86, blue: 0.62, alpha: 1)
    )
    static let comment = ColorRolePair(
        light: NSColor(srgbRed: 0.42, green: 0.47, blue: 0.42, alpha: 1),
        dark: NSColor(srgbRed: 0.55, green: 0.60, blue: 0.55, alpha: 1)
    )
    static let documentationComment = ColorRolePair(
        light: NSColor(srgbRed: 0.36, green: 0.45, blue: 0.40, alpha: 1),
        dark: NSColor(srgbRed: 0.62, green: 0.73, blue: 0.62, alpha: 1)
    )
    static let `operator` = ColorRolePair(
        light: NSColor(srgbRed: 0.32, green: 0.33, blue: 0.35, alpha: 1),
        dark: NSColor(srgbRed: 0.75, green: 0.76, blue: 0.78, alpha: 1)
    )
    static let punctuation = ColorRolePair(
        light: NSColor(srgbRed: 0.32, green: 0.33, blue: 0.35, alpha: 1),
        dark: NSColor(srgbRed: 0.75, green: 0.76, blue: 0.78, alpha: 1)
    )
    static let preprocessor = ColorRolePair(
        light: NSColor(srgbRed: 0.55, green: 0.38, blue: 0.11, alpha: 1),
        dark: NSColor(srgbRed: 0.90, green: 0.73, blue: 0.42, alpha: 1)
    )
    static let attribute = ColorRolePair(
        light: NSColor(srgbRed: 0.55, green: 0.38, blue: 0.11, alpha: 1),
        dark: NSColor(srgbRed: 0.90, green: 0.73, blue: 0.42, alpha: 1)
    )
    static let label = ColorRolePair(
        light: NSColor(srgbRed: 0.55, green: 0.38, blue: 0.11, alpha: 1),
        dark: NSColor(srgbRed: 0.90, green: 0.73, blue: 0.42, alpha: 1)
    )
    static let constant = ColorRolePair(
        light: NSColor(srgbRed: 0.55, green: 0.13, blue: 0.62, alpha: 1),
        dark: NSColor(srgbRed: 0.82, green: 0.58, blue: 0.94, alpha: 1)
    )
    static let invalid = ColorRolePair(
        light: NSColor(srgbRed: 0.85, green: 0.10, blue: 0.10, alpha: 1),
        dark: NSColor(srgbRed: 1.0, green: 0.35, blue: 0.35, alpha: 1)
    )
    static let plain = ColorRolePair(
        light: NSColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 1),
        dark: NSColor(srgbRed: 0.90, green: 0.91, blue: 0.92, alpha: 1)
    )
}
