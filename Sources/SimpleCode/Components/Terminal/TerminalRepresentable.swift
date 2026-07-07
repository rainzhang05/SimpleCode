import AppKit
import SwiftTerm
import SwiftUI

/// Bridges SwiftTerm's AppKit `LocalProcessTerminalView` into SwiftUI. This is the
/// only file that imports SwiftTerm's view layer directly — everything else talks to
/// `TerminalSessionController`.
///
/// Uses SwiftTerm's standard AppKit rendering path. The optional Metal renderer is
/// intentionally not enabled in this phase (see architecture report §4).
struct TerminalRepresentable: NSViewRepresentable {
    let session: TerminalSessionController
    var isPanelVisible: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        applyAppearance(to: view)

        session.attach(view)
        session.setPanelVisible(isPanelVisible)
        session.startIfNeeded()

        return view
    }

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {
        applyAppearance(to: view)
        session.setPanelVisible(isPanelVisible)
        if session.consumeFocusRequest() {
            view.window?.makeFirstResponder(view)
        }
    }

    private func applyAppearance(to view: LocalProcessTerminalView) {
        // These are genuinely dynamic `NSColor`s (not a pre-resolved snapshot).
        // SwiftTerm reads `nativeBackgroundColor`/`nativeForegroundColor` fresh on
        // every draw via `.setFill()`/`.set()`, so a dynamic color re-resolves
        // itself automatically on light/dark changes without this method needing
        // to run again — the same mechanism `CodeTextView` relies on.
        view.nativeBackgroundColor = ColorRole.terminalBackgroundPair.dynamic
        view.nativeForegroundColor = ColorRole.terminalForegroundPair.dynamic
        view.caretColor = ColorRole.terminalForegroundPair.dynamic
        view.selectedTextBackgroundColor = ColorRole.editorSelectionPair.dynamic
    }

    @MainActor
    // SwiftTerm's delegate callbacks are invoked on the main thread but are not
    // annotated for Swift 6 actor isolation.
    final class Coordinator: NSObject, @preconcurrency LocalProcessTerminalViewDelegate {
        let session: TerminalSessionController

        init(session: TerminalSessionController) {
            self.session = session
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            session.recordTerminalSize(cols: newCols, rows: newRows)
        }

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            // Not surfaced anywhere in this phase (no window/tab title binding yet).
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            // Not tracked in this phase; a future Run-command feature could read
            // this to confirm the shell's current working directory before writing
            // a command into it.
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            session.recordTermination(exitCode: exitCode)
        }
    }
}
