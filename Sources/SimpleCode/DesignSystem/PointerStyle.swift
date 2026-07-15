import AppKit
import SwiftUI

/// A hit-test-transparent AppKit region that owns one cursor while the pointer is
/// inside it. AppKit cursor rectangles arbitrate correctly with embedded AppKit
/// controls, unlike process-global SwiftUI hover callbacks.
final class CursorTrackingView: NSView {
    private var cursor: NSCursor

    init(cursor: NSCursor) {
        self.cursor = cursor
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CursorTrackingView does not support NSCoder")
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func accessibilityIsIgnored() -> Bool {
        true
    }

    func updateCursor(_ cursor: NSCursor) {
        guard self.cursor !== cursor else { return }
        self.cursor = cursor
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: cursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor.set()
    }
}

private struct NativeCursorRegion: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> CursorTrackingView {
        CursorTrackingView(cursor: cursor)
    }

    func updateNSView(_ nsView: CursorTrackingView, context: Context) {
        nsView.updateCursor(cursor)
    }
}

extension View {
    /// Native SwiftUI controls use the platform pointer system. No global cursor
    /// mutation is needed, so scrolling controls underneath a stationary pointer
    /// does not generate cursor churn.
    func pointingHandCursor() -> some View {
        pointerStyle(.link)
    }

    /// Embedded AppKit surfaces can otherwise win cursor arbitration from nearby
    /// SwiftUI buttons. This transparent region gives the button one native owner.
    func nativePointingHandCursor() -> some View {
        overlay {
            NativeCursorRegion(cursor: .pointingHand)
        }
    }

    /// Owns the arrow cursor over SwiftUI chrome that overlays an NSTextView,
    /// so the editor I-beam does not bleed through.
    func nativeArrowCursor() -> some View {
        overlay {
            NativeCursorRegion(cursor: .arrow)
        }
    }
}

struct NativeResizeHandle: NSViewRepresentable {
    enum Axis: Equatable {
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
    }
}

final class ResizeTrackingView: NSView {
    var axis: NativeResizeHandle.Axis = .horizontal {
        didSet {
            guard oldValue != axis else { return }
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?
    var onIncrement: (() -> Void)?
    var onDecrement: (() -> Void)?
    private var previousDragLocation: NSPoint?
    private var trackingRegion: NSTrackingArea?
    private var isHovering = false {
        didSet {
            guard oldValue != isHovering else { return }
            needsDisplay = true
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingRegion {
            removeTrackingArea(trackingRegion)
        }
        let region = NSTrackingArea(
            rect: .zero,
            options: [
                .activeInKeyWindow,
                .inVisibleRect,
                .mouseEnteredAndExited,
                .enabledDuringMouseDrag,
            ],
            owner: self
        )
        addTrackingArea(region)
        trackingRegion = region
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: axis.cursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        axis.cursor.set()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        previousDragLocation = event.locationInWindow
        isHovering = true
        axis.cursor.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let previousDragLocation else { return }
        let location = event.locationInWindow
        self.previousDragLocation = location
        switch axis {
        case .horizontal:
            onDrag?(location.x - previousDragLocation.x)
        case .vertical:
            onDrag?(location.y - previousDragLocation.y)
        }
        // Resizing can relayout the view and re-arbitrate cursor rectangles.
        // Reassert the drag cursor after the callback so it stays stable even
        // when the pointer has moved beyond the narrow handle.
        axis.cursor.set()
    }

    override func mouseUp(with event: NSEvent) {
        guard previousDragLocation != nil else { return }
        previousDragLocation = nil
        let location = window == nil
            ? event.locationInWindow
            : convert(event.locationInWindow, from: nil)
        if bounds.contains(location) {
            axis.cursor.set()
        } else {
            NSCursor.arrow.set()
        }
        needsDisplay = true
        onEnd?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let active = isHovering || previousDragLocation != nil
        NSColor.labelColor.withAlphaComponent(active ? 0.34 : 0.14).setFill()
        let indicatorRect: NSRect
        switch axis {
        case .horizontal:
            let height = min(32, max(0, bounds.height - 4))
            indicatorRect = NSRect(
                x: bounds.midX - 1,
                y: bounds.midY - height / 2,
                width: 2,
                height: height
            )
        case .vertical:
            let width = min(32, max(0, bounds.width - 4))
            indicatorRect = NSRect(
                x: bounds.midX - width / 2,
                y: bounds.midY - 1,
                width: width,
                height: 2
            )
        }
        NSBezierPath(
            roundedRect: indicatorRect,
            xRadius: 1,
            yRadius: 1
        ).fill()
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
