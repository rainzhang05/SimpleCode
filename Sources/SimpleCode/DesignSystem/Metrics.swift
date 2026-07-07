import CoreGraphics

/// A restrained spacing scale. Every layout in the app should reuse one of these
/// values rather than introducing arbitrary magic numbers.
enum Spacing {
    static let xxSmall: CGFloat = 4
    static let xSmall: CGFloat = 8
    static let small: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let xLarge: CGFloat = 32
}

/// A restrained corner-geometry scale.
///
/// macOS 26 (our minimum target) ships `ConcentricRectangle` / `.rect(corner:
/// .containerConcentric)`, which is the preferred way to keep nested rounded chrome
/// mathematically consistent with an enclosing container's corners. That API is used
/// directly in `GlassSurface.swift`. The fixed radii below are for the few surfaces
/// that are *not* nested inside another rounded container (e.g. the welcome screen's
/// action cards), where a concentric relationship doesn't apply.
enum CornerRadius {
    static let control: CGFloat = 8
    static let panel: CGFloat = 14
    static let card: CGFloat = 20
}
