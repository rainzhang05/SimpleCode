import SwiftUI

struct WorkspaceTrustSheet: View {
    let workspacePath: String
    let command: String
    var onCancel: () -> Void
    var onRunOnce: () -> Void
    var onTrustAndRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("Trust Workspace Before Running")
                .font(.headline)
                .accessibilityIdentifier("trust.sheet.title")

            Text("SimpleCode is about to send a command to your local shell.")
                .font(.system(size: 12))

            Group {
                LabeledContent("Workspace") {
                    Text(workspacePath)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                LabeledContent("Command") {
                    Text(command)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(3)
                }
            }
            .font(.system(size: 12))

            Text("Commands can read, modify, or delete files and access user data. Cloned repositories may contain untrusted scripts.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .pointingHandCursor()
                .accessibilityIdentifier("trust.sheet.cancel")
                Spacer()
                Button("Run Once") {
                    onRunOnce()
                }
                .pointingHandCursor()
                .accessibilityIdentifier("trust.sheet.runOnce")
                Button("Trust Workspace and Run") {
                    onTrustAndRun()
                }
                .buttonStyle(.borderedProminent)
                .pointingHandCursor()
                .accessibilityIdentifier("trust.sheet.trustAndRun")
            }
        }
        .padding(Spacing.large)
        .frame(width: 480)
        .background(WindowAccessibilityConfigurator(
            title: "Trust Workspace Before Running",
            identifier: "trust.sheet.window"
        ))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trust.sheet")
        .accessibilityAddTraits(.isModal)
    }
}
