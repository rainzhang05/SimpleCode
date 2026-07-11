import SwiftUI

struct RunConfigurationPopover: View {
    @Bindable var workspace: WorkspaceModel
    @Binding var isPresented: Bool

    @State private var draftCommand: String = ""
    @State private var revealTerminal: Bool = true
    @State private var clearTerminal: Bool = false
    @FocusState private var isCommandFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                Text("Run Command")
                    .font(.headline)

                TextField("Command", text: $draftCommand)
                    .textFieldStyle(.roundedBorder)
                    .focused($isCommandFocused)
                    .accessibilityIdentifier("run.popover.commandField")

                Text("Runs in the terminal's current shell directory, preserving environment and virtual environments.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let suggestion = workspace.runCommands.latestSuggestion, !suggestion.reason.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                        Text("Suggestion")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(suggestion.reason)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if suggestion.isRunnable, let command = suggestion.command {
                            Text(command)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(2)
                                .truncationMode(.middle)
                            Button("Use Suggestion") {
                                draftCommand = command
                            }
                            .pointingHandCursor()
                            .accessibilityIdentifier("run.popover.useSuggestion")
                        }
                    }
                    .accessibilityIdentifier("run.popover.suggestion")
                }

                Toggle("Reveal terminal on Run", isOn: $revealTerminal)
                    .font(.system(size: 12))
                    .accessibilityIdentifier("run.popover.revealTerminal")

                Toggle("Clear terminal before Run", isOn: $clearTerminal)
                    .font(.system(size: 12))
                    .accessibilityIdentifier("run.popover.clearTerminal")

                if workspace.trust.isTrusted {
                    Button("Mark Workspace as Untrusted") {
                        workspace.trust.markUntrusted()
                    }
                    .pointingHandCursor()
                    .font(.system(size: 11))
                    .accessibilityIdentifier("run.popover.markUntrusted")
                } else {
                    Button("Mark Workspace as Trusted") {
                        workspace.trust.markTrusted()
                    }
                    .pointingHandCursor()
                    .font(.system(size: 11))
                    .accessibilityIdentifier("run.popover.markTrusted")
                }

                HStack {
                    Spacer()
                    Button("Done") {
                        saveAndDismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .pointingHandCursor()
                }
            }
            .padding(Spacing.medium)
        }
        .frame(width: 360)
        .frame(maxHeight: 420)
        .onAppear {
            draftCommand = workspace.runCommands.configuration.command
            revealTerminal = workspace.runCommands.configuration.revealTerminalOnRun
            clearTerminal = workspace.runCommands.configuration.clearTerminalBeforeRun
            isCommandFocused = true
            Task { await workspace.runCommands.refreshSuggestion(rootURL: workspace.rootURL) }
        }
        .onExitCommand {
            isPresented = false
        }
    }

    private func saveAndDismiss() {
        workspace.runCommands.persistEdits(
            command: draftCommand,
            revealTerminal: revealTerminal,
            clearTerminal: clearTerminal
        )
        isPresented = false
    }
}
