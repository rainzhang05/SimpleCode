import AppKit
import Testing
@testable import SimpleCode

/// Light/dark color-role resolution — the part of `ColorRolePair` that does not
/// require a live drawing context, so it is directly testable.
struct ColorRoleTests {
    @Test func resolvedPicksLightWhenNotDark() {
        let pair = ColorRolePair(light: .red, dark: .blue)
        #expect(pair.resolved(isDark: false) == .red)
    }

    @Test func resolvedPicksDarkWhenDark() {
        let pair = ColorRolePair(light: .red, dark: .blue)
        #expect(pair.resolved(isDark: true) == .blue)
    }

    @Test func editorRolesDefineDifferentColorsForLightAndDark() {
        #expect(ColorRole.editorBackgroundPair.light != ColorRole.editorBackgroundPair.dark)
        #expect(ColorRole.editorForegroundPair.light != ColorRole.editorForegroundPair.dark)
        #expect(ColorRole.terminalBackgroundPair.light != ColorRole.terminalBackgroundPair.dark)
    }

    @Test func semanticAppearanceDefaultsUseNeutralCanvasInkAndSystemBlueCues() throws {
        try expectRGBA(ColorRoleDefaults.editorBackground.light, 1, 1, 1, 1)
        try expectRGBA(ColorRoleDefaults.editorBackground.dark, 11.0 / 255, 12.0 / 255, 14.0 / 255, 1)
        try expectRGBA(ColorRoleDefaults.editorForeground.light, 21.0 / 255, 23.0 / 255, 26.0 / 255, 1)
        try expectRGBA(ColorRoleDefaults.editorForeground.dark, 245.0 / 255, 247.0 / 255, 250.0 / 255, 1)
        try expectRGBA(ColorRoleDefaults.editorSelection.light, 0, 122.0 / 255, 1, 0.22)
        try expectRGBA(ColorRoleDefaults.editorSelection.dark, 10.0 / 255, 132.0 / 255, 1, 0.30)
        try expectRGBA(ColorRoleDefaults.editorCurrentLine.light, 0, 122.0 / 255, 1, 0.055)
        try expectRGBA(ColorRoleDefaults.editorCurrentLine.dark, 10.0 / 255, 132.0 / 255, 1, 0.10)
        try expectRGBA(ColorRoleDefaults.gutterBackground.light, 248.0 / 255, 249.0 / 255, 250.0 / 255, 1)
        try expectRGBA(ColorRoleDefaults.gutterBackground.dark, 17.0 / 255, 19.0 / 255, 23.0 / 255, 1)
        try expectRGBA(ColorRoleDefaults.lineNumber.light, 107.0 / 255, 114.0 / 255, 128.0 / 255, 1)
        try expectRGBA(ColorRoleDefaults.lineNumber.dark, 139.0 / 255, 148.0 / 255, 158.0 / 255, 1)
        try expectRGBA(ColorRoleDefaults.activeLineNumber.light, 21.0 / 255, 23.0 / 255, 26.0 / 255, 1)
        try expectRGBA(ColorRoleDefaults.activeLineNumber.dark, 245.0 / 255, 247.0 / 255, 250.0 / 255, 1)
        try expectRGBA(ColorRoleDefaults.longLineGuide.light, 0, 0, 0, 0.08)
        try expectRGBA(ColorRoleDefaults.longLineGuide.dark, 1, 1, 1, 0.10)
        try expectRGBA(ColorRoleDefaults.whitespaceMarker.light, 0, 0, 0, 0.18)
        try expectRGBA(ColorRoleDefaults.whitespaceMarker.dark, 1, 1, 1, 0.20)
        try expectRGBA(ColorRoleDefaults.terminalBackground.light, 1, 1, 1, 1)
        try expectRGBA(ColorRoleDefaults.terminalBackground.dark, 11.0 / 255, 12.0 / 255, 14.0 / 255, 1)
        try expectRGBA(ColorRoleDefaults.terminalForeground.light, 21.0 / 255, 23.0 / 255, 26.0 / 255, 1)
        try expectRGBA(ColorRoleDefaults.terminalForeground.dark, 245.0 / 255, 247.0 / 255, 250.0 / 255, 1)
    }

    @Test func legacyVioletDefaultsRetainExactMigrationValues() throws {
        try expectRGBA(LegacyVioletColorRoleDefaults.editorBackground.light, 1, 0.988, 1, 1)
        try expectRGBA(LegacyVioletColorRoleDefaults.editorBackground.dark, 0.090, 0.078, 0.129, 1)
        try expectRGBA(LegacyVioletColorRoleDefaults.editorForeground.light, 0.114, 0.094, 0.188, 1)
        try expectRGBA(LegacyVioletColorRoleDefaults.editorForeground.dark, 0.957, 0.941, 1, 1)
        try expectRGBA(LegacyVioletColorRoleDefaults.editorCurrentLine.light, 0.404, 0.341, 0.914, 0.075)
        try expectRGBA(LegacyVioletColorRoleDefaults.editorCurrentLine.dark, 0.706, 0.659, 1, 0.14)
        try expectRGBA(LegacyVioletColorRoleDefaults.editorSelection.light, 0.404, 0.341, 0.914, 0.24)
        try expectRGBA(LegacyVioletColorRoleDefaults.editorSelection.dark, 0.706, 0.659, 1, 0.36)
        try expectRGBA(LegacyVioletColorRoleDefaults.gutterBackground.light, 0.961, 0.945, 1, 1)
        try expectRGBA(LegacyVioletColorRoleDefaults.gutterBackground.dark, 0.125, 0.106, 0.173, 1)
        try expectRGBA(LegacyVioletColorRoleDefaults.lineNumber.light, 0.400, 0.365, 0.490, 1)
        try expectRGBA(LegacyVioletColorRoleDefaults.lineNumber.dark, 0.690, 0.647, 0.780, 1)
        try expectRGBA(LegacyVioletColorRoleDefaults.activeLineNumber.light, 0.231, 0.192, 0.341, 1)
        try expectRGBA(LegacyVioletColorRoleDefaults.activeLineNumber.dark, 0.925, 0.898, 1, 1)
        try expectRGBA(LegacyVioletColorRoleDefaults.longLineGuide.light, 0.404, 0.341, 0.914, 0.22)
        try expectRGBA(LegacyVioletColorRoleDefaults.longLineGuide.dark, 0.706, 0.659, 1, 0.32)
        try expectRGBA(LegacyVioletColorRoleDefaults.whitespaceMarker.light, 0.424, 0.365, 0.600, 0.34)
        try expectRGBA(LegacyVioletColorRoleDefaults.whitespaceMarker.dark, 0.710, 0.659, 0.835, 0.38)
        try expectRGBA(LegacyVioletColorRoleDefaults.terminalBackground.light, 0.090, 0.067, 0.157, 1)
        try expectRGBA(LegacyVioletColorRoleDefaults.terminalBackground.dark, 0.055, 0.039, 0.094, 1)
        try expectRGBA(LegacyVioletColorRoleDefaults.terminalForeground.light, 0.965, 0.941, 1, 1)
        try expectRGBA(LegacyVioletColorRoleDefaults.terminalForeground.dark, 0.965, 0.941, 1, 1)
    }

    @Test func chromeFoundationUsesAdaptiveNeutralsAndSystemBlue() throws {
        try expectRGBA(ColorRole.chromeFallbackPair.light, 1, 1, 1, 1)
        try expectRGBA(ColorRole.chromeFallbackPair.dark, 11.0 / 255, 12.0 / 255, 14.0 / 255, 1)
        try expectRGBA(ColorRole.chromeInkPair.light, 21.0 / 255, 23.0 / 255, 26.0 / 255, 1)
        try expectRGBA(ColorRole.chromeInkPair.dark, 245.0 / 255, 247.0 / 255, 250.0 / 255, 1)
        try expectRGBA(ColorRole.chromeHairlinePair.light, 0, 0, 0, 0.08)
        try expectRGBA(ColorRole.chromeHairlinePair.dark, 1, 1, 1, 0.10)
        #expect(ColorRole.chromeAccentNSColor == .systemBlue)
    }

    private func expectRGBA(
        _ color: NSColor,
        _ red: Double,
        _ green: Double,
        _ blue: Double,
        _ alpha: Double
    ) throws {
        let converted = try #require(color.usingColorSpace(.sRGB))
        #expect(abs(Double(converted.redComponent) - red) < 0.000_1)
        #expect(abs(Double(converted.greenComponent) - green) < 0.000_1)
        #expect(abs(Double(converted.blueComponent) - blue) < 0.000_1)
        #expect(abs(Double(converted.alphaComponent) - alpha) < 0.000_1)
    }
}
