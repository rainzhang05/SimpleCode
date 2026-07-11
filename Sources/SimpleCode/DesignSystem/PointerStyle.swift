import AppKit
import SwiftUI

/// Installs a native AppKit cursor rect instead of manipulating the global cursor
/// stack from SwiftUI hover callbacks. Cursor rects remain correct when buttons are
/// recycled, clipped, or layered above AppKit-backed editor and terminal views.
private struct PointingHandCursorRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> CursorRegionView {
        CursorRegionView()
    }

    func updateNSView(_ nsView: CursorRegionView, context: Context) {
        nsView.invalidateCursorRegions()
    }

    final class CursorRegionView: NSView {
        override var isOpaque: Bool { false }

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Keep the host control's click, keyboard, and accessibility behavior
            // untouched. Cursor rectangles do not require this view to win hit tests.
            nil
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .pointingHand)
        }

        override func layout() {
            super.layout()
            invalidateCursorRegions()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            invalidateCursorRegions()
        }

        override func accessibilityIsIgnored() -> Bool {
            true
        }

        func invalidateCursorRegions() {
            window?.invalidateCursorRects(for: self)
        }
    }
}

extension View {
    /// Use for non-text interactive controls that should show the standard pointing
    /// hand without leaking a pushed cursor into neighboring AppKit content.
    func pointingHandCursor() -> some View {
        overlay {
            PointingHandCursorRegion()
        }
    }
}
