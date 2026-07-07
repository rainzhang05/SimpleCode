import SwiftUI

/// SwiftUI chrome around the terminal: a compact glass header (Clear / Restart /
/// Close) plus the AppKit-bridged terminal surface itself, which stays opaque per
/// the design system's rule that glass never sits behind text content.
struct TerminalPanelView: View {
    @Bindable var session: TerminalSessionController
    var isVisible: Bool = true
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if isVisible {
                header
            }
            TerminalRepresentable(session: session, isPanelVisible: isVisible)
                .opacity(isVisible ? 1 : 0)
                .allowsHitTesting(isVisible)
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.small) {
            Text("Terminal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ColorRole.statusBarText)

            Spacer()

            Button {
                session.clearScreen()
            } label: {
                Label("Clear", systemImage: "eraser")
            }
            .help("Clear the terminal display")

            Button {
                session.restart()
            } label: {
                Label("Restart", systemImage: "arrow.clockwise")
            }
            .help("Restart the shell session")
            .accessibilityIdentifier("terminal.restartButton")

            Button {
                onClose()
            } label: {
                Label("Close", systemImage: "xmark")
            }
            .help("Hide the terminal panel")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.xxSmall)
        .frame(height: 28)
        .glassPanel(cornerRadius: CornerRadius.control)
        .padding(.horizontal, Spacing.xxSmall)
        .padding(.top, Spacing.xxSmall)
    }
}
