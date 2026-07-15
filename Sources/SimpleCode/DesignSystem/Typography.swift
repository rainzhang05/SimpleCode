import AppKit

/// Monospaced font helpers shared by the editor and terminal surfaces.
enum Typography {
    static let defaultEditorFontSize: CGFloat = 13
    static let minimumEditorFontSize: CGFloat = 9
    static let maximumEditorFontSize: CGFloat = 36
    static let systemMonospacedFamilyName = ".AppleSystemUIFontMonospaced"

    static func editorFont(family: String, size: CGFloat, ligatures: Bool) -> NSFont {
        let resolvedFamily = FontCatalog.resolvedMonospacedFamily(family)
        if let font = NSFont(name: resolvedFamily, size: size) {
            if ligatures {
                return font
            }
            let descriptor = font.fontDescriptor.addingAttributes([
                .featureSettings: [[
                    NSFontDescriptor.FeatureKey.typeIdentifier: kLigaturesType,
                    NSFontDescriptor.FeatureKey.selectorIdentifier: kCommonLigaturesOffSelector
                ]]
            ])
            return NSFont(descriptor: descriptor, size: size) ?? font
        }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func terminalFont(family: String, size: CGFloat) -> NSFont {
        let resolvedFamily = FontCatalog.resolvedMonospacedFamily(family)
        return NSFont(name: resolvedFamily, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

/// Cached list of installed monospaced fonts for Settings pickers.
enum FontCatalog {
    nonisolated(unsafe) private static var cachedFamilies: [String]?

    static var monospacedFamilies: [String] {
        if let cachedFamilies { return cachedFamilies }
        let families = NSFontManager.shared.availableFontFamilies.filter { family in
            guard let font = NSFont(name: family, size: 12) else { return false }
            return font.isFixedPitch
        }.sorted()
        cachedFamilies = [Typography.systemMonospacedFamilyName] + families.filter { $0 != Typography.systemMonospacedFamilyName }
        return cachedFamilies!
    }

    static func resolvedMonospacedFamily(_ family: String) -> String {
        if family == Typography.systemMonospacedFamilyName { return family }
        if monospacedFamilies.contains(family) { return family }
        return Typography.systemMonospacedFamilyName
    }

    static func displayName(for family: String) -> String {
        family == Typography.systemMonospacedFamilyName ? "System Monospaced" : family
    }
}
