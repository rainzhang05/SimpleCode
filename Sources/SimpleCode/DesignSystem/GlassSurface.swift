import SwiftUI

/// Reusable Liquid Glass wrappers for navigation/control surfaces.
///
/// Per the design direction: glass is used for chrome (toolbars, panel headers,
/// popovers, the welcome screen's action cards) and never behind the editor or
/// terminal text surfaces, which stay stable and opaque (`ColorRole.editorBackground`
/// / `ColorRole.terminalBackground`).
///
/// The minimum deployment target is macOS 26, so `.glassEffect()` is unconditionally
/// available — no `#available` branching is required for the baseline behavior here.
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = CornerRadius.panel
    var isInteractive: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content
                .background(Color(nsColor: .controlBackgroundColor), in: shape)
        } else {
            let variant: Glass = (isInteractive && !reduceMotion) ? .regular.interactive() : .regular
            content
                .glassEffect(variant, in: shape)
        }
    }
}

extension View {
    /// Wraps content in a rounded Liquid Glass surface suitable for floating chrome
    /// (panel headers, popovers, action cards). Not intended for large bodies of text.
    func glassPanel(cornerRadius: CGFloat = CornerRadius.panel, interactive: Bool = false) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius, isInteractive: interactive))
    }
}
