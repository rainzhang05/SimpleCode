import SwiftUI

extension View {
    /// Uses SwiftUI's native pointing-hand pointer without adding an overlay view
    /// that can affect hit testing, layout, or accessibility.
    func pointingHandCursor() -> some View {
        pointerStyle(.link)
    }
}
