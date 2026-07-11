import AppKit
import SwiftUI

struct WindowAccessibilityConfigurator: NSViewRepresentable {
    let title: String
    let identifier: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureWindow(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureWindow(for: nsView)
    }

    private func configureWindow(for view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.title = title
            window.setAccessibilityIdentifier(identifier)
        }
    }
}
