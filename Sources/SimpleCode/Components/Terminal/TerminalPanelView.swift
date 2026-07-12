import SwiftUI

/// SwiftUI chrome around the terminal: a compact glass header (Clear /
/// Close) plus the AppKit-bridged terminal surface itself, which stays opaque per
/// the design system's rule that glass never sits behind text content.
struct TerminalPanelView: View {
    @Bindable var session: TerminalSessionController
    let typography: TypographySettings
    let terminalSettings: TerminalAppearanceSettings
    @Binding var panelHeight: CGFloat
    var isVisible: Bool = true
    var onClose: () -> Void

    @State private var resizeStartHeight: CGFloat?
    @State private var isResizeHandleHovered = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .opacity(0.35)
            TerminalRepresentable(
                session: session,
                typography: typography,
                terminalSettings: terminalSettings,
                isPanelVisible: isVisible
            )
                .accessibilityIdentifier("terminal.surface")
                .opacity(isVisible ? 1 : 0)
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
        Rectangle()
            .fill(.clear)
            .frame(height: 14)
            .contentShape(Rectangle())
            .overlay {
                Capsule()
                    .fill(.primary.opacity(isResizeHandleHovered ? 0.34 : 0.14))
                    .frame(width: 32, height: 2)
            }
            .onHover { isResizeHandleHovered = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let startHeight = resizeStartHeight ?? panelHeight
                        if resizeStartHeight == nil { resizeStartHeight = startHeight }
                        panelHeight = startHeight - value.translation.height
                    }
                    .onEnded { _ in
                        resizeStartHeight = nil
                    }
            )
            .pointingHandCursor()
            .accessibilityElement()
            .accessibilityLabel("Resize Terminal")
            .accessibilityValue("\(Int(panelHeight)) points")
            .accessibilityIdentifier("terminal.resizeHandle")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    panelHeight += 16
                case .decrement:
                    panelHeight -= 16
                @unknown default:
                    break
                }
            }
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
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.glass)
        .help(help)
        .pointingHandCursor()
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
