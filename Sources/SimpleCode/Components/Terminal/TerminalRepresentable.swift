import AppKit
import SwiftTerm
import SwiftUI

/// Bridges SwiftTerm's AppKit `LocalProcessTerminalView` into SwiftUI. This is the
/// only file that imports SwiftTerm's view layer directly — everything else talks to
/// `TerminalSessionController`.
///
/// Uses SwiftTerm's standard AppKit rendering path. The optional Metal renderer is
/// intentionally not enabled in this phase (see architecture report §4).
@MainActor
struct TerminalRepresentable: NSViewRepresentable {
    let session: TerminalSessionController
    let typography: TypographySettings
    let terminalSettings: TerminalAppearanceSettings
    var isPanelVisible: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        view.isHidden = !isPanelVisible
        applyAppearance(to: view, coordinator: context.coordinator)

        context.coordinator.attach(view)
        session.setPanelVisible(isPanelVisible)

        return view
    }

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {
        view.isHidden = !isPanelVisible
        applyAppearance(to: view, coordinator: context.coordinator)
        session.setPanelVisible(isPanelVisible)
        if session.consumeFocusRequest() {
            if view.window?.makeFirstResponder(view) != true {
                session.focusTerminal()
            }
        }
    }

    static func dismantleNSView(_ view: LocalProcessTerminalView, coordinator: Coordinator) {
        coordinator.detach()
    }

    private func applyAppearance(to view: LocalProcessTerminalView, coordinator: Coordinator) {
        // These are genuinely dynamic `NSColor`s (not a pre-resolved snapshot).
        // SwiftTerm reads `nativeBackgroundColor`/`nativeForegroundColor` fresh on
        // every draw via `.setFill()`/`.set()`, so a dynamic color re-resolves
        // itself automatically on light/dark changes without this method needing
        // to run again — the same mechanism `CodeTextView` relies on.
        view.nativeBackgroundColor = ColorRole.terminalBackgroundPair.dynamic
        view.nativeForegroundColor = ColorRole.terminalForegroundPair.dynamic
        view.caretColor = ColorRole.terminalForegroundPair.dynamic
        view.selectedTextBackgroundColor = ColorRole.editorSelectionPair.dynamic
        coordinator.applySupportedSettings(
            to: view,
            typography: typography,
            terminalSettings: terminalSettings
        )
    }

    @MainActor
    // SwiftTerm's delegate callbacks are invoked on the main thread but are not
    // annotated for Swift 6 actor isolation.
    final class Coordinator: NSObject, @preconcurrency LocalProcessTerminalViewDelegate {
        let session: TerminalSessionController
        private var driver: SwiftTermTerminalDriver?
        private var attachmentID: UUID?
        private var appliedFont: AppliedFont?
        private var appliedScrollbackLimit: Int?

        init(session: TerminalSessionController) {
            self.session = session
        }

        func attach(_ view: LocalProcessTerminalView) {
            let driver = SwiftTermTerminalDriver(view: view)
            self.driver = driver
            attachmentID = session.attach(driver)
        }

        func detach() {
            if let attachmentID {
                session.detach(attachmentID)
            }
            attachmentID = nil
            driver = nil
        }

        func applySupportedSettings(
            to view: LocalProcessTerminalView,
            typography: TypographySettings,
            terminalSettings: TerminalAppearanceSettings
        ) {
            let font = Typography.terminalFont(
                family: typography.terminalFontFamily,
                size: CGFloat(typography.terminalFontSize)
            )
            let requestedFont = AppliedFont(name: font.fontName, pointSize: font.pointSize)
            if appliedFont != requestedFont {
                view.font = font
                appliedFont = requestedFont
            }

            if appliedScrollbackLimit != terminalSettings.scrollbackLimit {
                view.changeScrollback(terminalSettings.scrollbackLimit)
                appliedScrollbackLimit = terminalSettings.scrollbackLimit
            }
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
            session.recordTermination(exitCode: exitCode, from: attachmentID)
        }

        private struct AppliedFont: Equatable {
            let name: String
            let pointSize: CGFloat
        }
    }
}

@MainActor
private final class SwiftTermTerminalDriver: TerminalSessionDriving {
    private weak var view: LocalProcessTerminalView?

    init(view: LocalProcessTerminalView) {
        self.view = view
    }

    var isProcessRunning: Bool {
        guard let view else { return false }
        return view.process.running
    }

    func startProcess(executable: String, environment: [String], currentDirectory: String) {
        view?.startProcess(
            executable: executable,
            environment: environment,
            currentDirectory: currentDirectory
        )
    }

    func send(text: String) -> Bool {
        guard let view, view.process.running else { return false }
        view.send(txt: text)
        return true
    }

    func send(bytes: [UInt8]) -> Bool {
        guard let view, view.process.running else { return false }
        view.send(bytes)
        return true
    }

    func clearDisplay() {
        guard let view else { return }
        view.terminal.buffer.clear()
        view.terminal.buffer.fillViewportRows()
        view.needsDisplay = true
    }

    func focus() -> Bool {
        guard let view, let window = view.window else { return false }
        return window.makeFirstResponder(view)
    }

    func terminate() {
        view?.terminate()
    }

    func resize(cols: Int, rows: Int) {
        view?.resize(cols: cols, rows: rows)
    }
}
