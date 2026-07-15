import AppKit
import SwiftUI

private struct ReliablePointerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .pointerStyle(.link)
            .onHover { isInside in
                if isInside {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
    }
}

extension View {
    func pointingHandCursor() -> some View {
        modifier(ReliablePointerModifier())
    }
}

struct NativeResizeHandle: NSViewRepresentable {
    enum Axis {
        case horizontal
        case vertical

        var cursor: NSCursor {
            switch self {
            case .horizontal: .resizeLeftRight
            case .vertical: .resizeUpDown
            }
        }
    }

    let axis: Axis
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let accessibilityValue: String
    let onDrag: (CGFloat) -> Void
    let onEnd: () -> Void
    let onIncrement: () -> Void
    let onDecrement: () -> Void

    func makeNSView(context: Context) -> ResizeTrackingView {
        let view = ResizeTrackingView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: ResizeTrackingView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: ResizeTrackingView) {
        view.axis = axis
        view.onDrag = onDrag
        view.onEnd = onEnd
        view.onIncrement = onIncrement
        view.onDecrement = onDecrement
        view.setAccessibilityElement(true)
        view.setAccessibilityEnabled(true)
        view.setAccessibilityRole(.splitter)
        view.setAccessibilityLabel(accessibilityLabel)
        view.setAccessibilityIdentifier(accessibilityIdentifier)
        view.setAccessibilityValue(accessibilityValue)
        view.window?.invalidateCursorRects(for: view)
    }
}

final class ResizeTrackingView: NSView {
    var axis: NativeResizeHandle.Axis = .horizontal
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?
    var onIncrement: (() -> Void)?
    var onDecrement: (() -> Void)?
    private var dragOrigin: NSPoint?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: axis.cursor)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragOrigin = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOrigin else { return }
        let location = event.locationInWindow
        switch axis {
        case .horizontal:
            onDrag?(location.x - dragOrigin.x)
        case .vertical:
            onDrag?(location.y - dragOrigin.y)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard dragOrigin != nil else { return }
        dragOrigin = nil
        onEnd?()
    }

    override func accessibilityPerformIncrement() -> Bool {
        onIncrement?()
        return onIncrement != nil
    }

    override func accessibilityPerformDecrement() -> Bool {
        onDecrement?()
        return onDecrement != nil
    }

    override func keyDown(with event: NSEvent) {
        switch (axis, event.keyCode) {
        case (.horizontal, 124), (.vertical, 126):
            onIncrement?()
        case (.horizontal, 123), (.vertical, 125):
            onDecrement?()
        default:
            super.keyDown(with: event)
        }
    }
}
