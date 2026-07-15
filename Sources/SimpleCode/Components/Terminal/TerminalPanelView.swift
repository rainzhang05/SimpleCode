import SwiftUI

/// SwiftUI chrome around the terminal: a compact glass header (Clear /
/// Close) plus the AppKit-bridged terminal surface itself, which stays opaque per
/// the design system's rule that glass never sits behind text content.
struct TerminalPanelView: View {
    @Bindable var session: TerminalSessionController
    let settings: AppSettingsSnapshot
    @Binding var panelHeight: CGFloat
    var isVisible: Bool = true
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .opacity(0.35)
            TerminalRepresentable(
                session: session,
                settings: settings,
                isPanelVisible: isVisible
            )
                .accessibilityIdentifier("terminal.surface")
                .allowsHitTesting(isVisible)
                .background(Color(nsColor: ColorRole.terminalBackgroundPair.dynamic))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.control, style: .continuous))
                .padding(.horizontal, Spacing.xSmall)
                .padding(.bottom, Spacing.xSmall)
        }
        .padding(.top, Spacing.xSmall)
        .glassPanel(cornerRadius: CornerRadius.panel)
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.panel, style: .continuous))
        .overlay(alignment: .top) {
            resizeHandle
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("terminal.panel")
        .accessibilityHidden(!isVisible)
    }

    private var resizeHandle: some View {
        NativeResizeHandle(
            axis: .vertical,
            accessibilityLabel: "Resize Terminal",
            accessibilityIdentifier: "terminal.resizeHandle",
            accessibilityValue: "\(Int(panelHeight)) points"
        ) { translation in
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                panelHeight += translation
            }
        } onEnd: {} onIncrement: {
            panelHeight += 16
        } onDecrement: {
            panelHeight -= 16
        }
            .frame(height: 14)
            .contentShape(Rectangle())
    }

    private var header: some View {
        HStack(spacing: Spacing.small) {
            HStack(spacing: 7) {
                Circle()
                    .fill(sessionIndicatorColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Terminal")
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(sessionStateLabel) · \(session.workingDirectory.lastPathComponent)")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(ColorRole.statusBarText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Terminal \(sessionStateLabel), \(session.workingDirectory.path)")

            Spacer()

            terminalAction(
                title: "Clear Terminal",
                systemImage: "eraser",
                help: "Clear the terminal display",
                identifier: "terminal.clearButton",
                action: session.clearDisplay
            )
            terminalAction(
                title: "Close Terminal",
                systemImage: "xmark",
                help: "Hide the terminal panel",
                identifier: "terminal.closeButton",
                action: onClose
            )
        }
        .padding(.horizontal, Spacing.small)
        .frame(height: 36)
        .accessibilityElement(children: .contain)
    }

    private func terminalAction(
        title: String,
        systemImage: String,
        help: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .frame(width: 24, height: 24)
        .contentShape(Circle())
        .help(help)
        .nativePointingHandCursor()
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    private var sessionStateLabel: String {
        switch session.state {
        case .notStarted: "Ready"
        case .running: "Connected"
        case .terminated(let code):
            code.map { "Exited \($0)" } ?? "Stopped"
        }
    }

    private var sessionIndicatorColor: Color {
        switch session.state {
        case .running: .green
        case .notStarted: .secondary
        case .terminated: .orange
        }
    }
}
