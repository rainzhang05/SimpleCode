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
    private final class SnapshotStorage: @unchecked Sendable {
        private let lock = NSLock()
        private var value = AppSettingsSnapshot.defaults

        func read() -> AppSettingsSnapshot {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func write(_ snapshot: AppSettingsSnapshot) {
            lock.lock()
            value = snapshot
            lock.unlock()
        }
    }

    private static let storage = SnapshotStorage()

    @MainActor
    static func bind(_ settings: AppSettingsStore) {
        updateSnapshot(settings.snapshot)
    }

    static func updateSnapshot(_ snapshot: AppSettingsSnapshot) {
        storage.write(snapshot)
    }

    static var snapshot: AppSettingsSnapshot { storage.read() }

    static var appearance: AppearanceSettings { snapshot.appearance }

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

    static let chromeFallbackPair = ColorRolePair(
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        dark: NSColor(srgbRed: 11.0 / 255, green: 12.0 / 255, blue: 14.0 / 255, alpha: 1)
    )
    static let chromeInkPair = ColorRolePair(
        light: NSColor(srgbRed: 21.0 / 255, green: 23.0 / 255, blue: 26.0 / 255, alpha: 1),
        dark: NSColor(srgbRed: 245.0 / 255, green: 247.0 / 255, blue: 250.0 / 255, alpha: 1)
    )
    static let chromeHairlinePair = ColorRolePair(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.08),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10)
    )

    static let chromeFallback = Color(nsColor: chromeFallbackPair.dynamic)
    static let chromeAccentNSColor = NSColor.systemBlue
    static let chromeAccent = Color(nsColor: chromeAccentNSColor)
    static let chromeHairline = Color(nsColor: chromeHairlinePair.dynamic)
    static let statusBarText = Color(nsColor: chromeInkPair.dynamic).opacity(0.74)
}
