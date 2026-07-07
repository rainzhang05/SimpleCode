import AppKit
import SwiftUI

struct ColorRolePair {
    let light: NSColor
    let dark: NSColor

    func resolved(isDark: Bool) -> NSColor { isDark ? dark : light }

    var dynamic: NSColor {
        let light = self.light
        let dark = self.dark
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}

/// Resolves editor/terminal colors from the active `AppSettingsStore`.
enum SettingsColorResolver {
    nonisolated(unsafe) private static var cachedAppearance: AppearanceSettings = .defaults

    @MainActor
    static func bind(_ settings: AppSettingsStore) {
        cachedAppearance = settings.appearance
    }

    nonisolated static func updateSnapshot(_ appearance: AppearanceSettings) {
        cachedAppearance = appearance
    }

    static var appearance: AppearanceSettings {
        cachedAppearance
    }

    static func pair(_ keyPath: KeyPath<AppearanceSettings, StoredColorPair>) -> ColorRolePair {
        appearance[keyPath: keyPath].colorRolePair
    }

    static func syntaxColor(for category: SyntaxCategory, isDark: Bool) -> NSColor {
        let palette = appearance.syntaxPalette
        let stored = palette.pair(for: category)
        return isDark ? stored.dark.nsColor : stored.light.nsColor
    }
}

enum ColorRole {
    // MARK: Editor surface (stable, opaque — never glass)

    static var editorBackgroundPair: ColorRolePair {
        SettingsColorResolver.pair(\.editorBackground)
    }
    static var editorBackgroundNSColor: NSColor { editorBackgroundPair.dynamic }
    static var editorBackground: Color { Color(nsColor: editorBackgroundNSColor) }

    static var editorForegroundPair: ColorRolePair {
        SettingsColorResolver.pair(\.editorForeground)
    }
    static var editorForegroundNSColor: NSColor { editorForegroundPair.dynamic }
    static var editorForeground: Color { Color(nsColor: editorForegroundNSColor) }

    static var editorLineNumberPair: ColorRolePair {
        SettingsColorResolver.pair(\.lineNumber)
    }
    static var editorLineNumberNSColor: NSColor { editorLineNumberPair.dynamic }

    static var editorLineNumberEmphasizedPair: ColorRolePair {
        SettingsColorResolver.pair(\.activeLineNumber)
    }
    static var editorLineNumberEmphasizedNSColor: NSColor { editorLineNumberEmphasizedPair.dynamic }

    static var editorCurrentLinePair: ColorRolePair {
        SettingsColorResolver.pair(\.editorCurrentLine)
    }
    static var editorCurrentLineNSColor: NSColor { editorCurrentLinePair.dynamic }

    static var editorSelectionPair: ColorRolePair {
        SettingsColorResolver.pair(\.editorSelection)
    }
    static var editorSelectionNSColor: NSColor { editorSelectionPair.dynamic }

    static var gutterBackgroundPair: ColorRolePair {
        SettingsColorResolver.pair(\.gutterBackground)
    }
    static var gutterBackgroundNSColor: NSColor { gutterBackgroundPair.dynamic }

    static var longLineGuidePair: ColorRolePair {
        SettingsColorResolver.pair(\.longLineGuide)
    }
    static var longLineGuideNSColor: NSColor { longLineGuidePair.dynamic }

    static var whitespaceMarkerPair: ColorRolePair {
        SettingsColorResolver.pair(\.whitespaceMarker)
    }
    static var whitespaceMarkerNSColor: NSColor { whitespaceMarkerPair.dynamic }

    // MARK: Terminal surface

    static var terminalBackgroundPair: ColorRolePair {
        SettingsColorResolver.pair(\.terminalBackground)
    }

    static var terminalForegroundPair: ColorRolePair {
        SettingsColorResolver.pair(\.terminalForeground)
    }

    // MARK: Chrome

    static let chromeHairline = Color.primary.opacity(0.08)
    static let statusBarText = Color.secondary
}
