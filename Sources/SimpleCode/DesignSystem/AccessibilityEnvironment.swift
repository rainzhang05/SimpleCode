import SwiftUI

extension View {
    /// Applies `animation` unless the user has requested Reduce Motion, in which case
    /// the state change still happens but without an animated transition.
    ///
    /// Used for chrome transitions (sidebar/terminal show-hide) — never for anything
    /// that would interfere with reading or editing code, per the design direction's
    /// "decorative animation must not interfere with coding" rule.
    @ViewBuilder
    func reduceMotionAwareAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(ReduceMotionAwareAnimationModifier(animation: animation, value: value))
    }
}

private struct ReduceMotionAwareAnimationModifier<V: Equatable>: ViewModifier {
    let animation: Animation?
    let value: V

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
