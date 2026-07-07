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
}
