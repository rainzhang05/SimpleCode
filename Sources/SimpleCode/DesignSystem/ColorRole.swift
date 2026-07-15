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

enum ColorRole {
    // MARK: Editor surface (stable, opaque — never glass)

    static let editorBackgroundPair = ColorRoleDefaults.editorBackground
    static var editorBackgroundNSColor: NSColor { editorBackgroundPair.dynamic }
    static var editorBackground: Color { Color(nsColor: editorBackgroundNSColor) }

    static let editorForegroundPair = ColorRoleDefaults.editorForeground
    static var editorForegroundNSColor: NSColor { editorForegroundPair.dynamic }

    static let editorLineNumberPair = ColorRoleDefaults.lineNumber
    static var editorLineNumberNSColor: NSColor { editorLineNumberPair.dynamic }

    static let editorLineNumberEmphasizedPair = ColorRoleDefaults.activeLineNumber
    static var editorLineNumberEmphasizedNSColor: NSColor { editorLineNumberEmphasizedPair.dynamic }

    static let editorCurrentLinePair = ColorRoleDefaults.editorCurrentLine
    static var editorCurrentLineNSColor: NSColor { editorCurrentLinePair.dynamic }

    static let editorSelectionPair = ColorRoleDefaults.editorSelection
    static var editorSelectionNSColor: NSColor { editorSelectionPair.dynamic }

    static let gutterBackgroundPair = ColorRoleDefaults.gutterBackground
    static var gutterBackgroundNSColor: NSColor { gutterBackgroundPair.dynamic }

    static let longLineGuidePair = ColorRoleDefaults.longLineGuide
    static var longLineGuideNSColor: NSColor { longLineGuidePair.dynamic }

    static let whitespaceMarkerPair = ColorRoleDefaults.whitespaceMarker
    static var whitespaceMarkerNSColor: NSColor { whitespaceMarkerPair.dynamic }

    // MARK: Terminal surface

    static let terminalBackgroundPair = ColorRoleDefaults.terminalBackground
    static let terminalForegroundPair = ColorRoleDefaults.terminalForeground

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
