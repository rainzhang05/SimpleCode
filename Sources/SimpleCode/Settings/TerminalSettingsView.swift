import SwiftUI

struct TerminalSettingsView: View {
    @Bindable var settings: AppSettingsStore

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Font Family", selection: $settings.terminal.fontFamily) {
                    ForEach(FontCatalog.monospacedFamilies, id: \.self) { family in
                        Text(FontCatalog.displayName(for: family)).tag(family)
                    }
                }
                Stepper(
                    "Font Size: \(Int(settings.terminal.fontSize))",
                    value: $settings.terminal.fontSize,
                    in: Double(Typography.minimumEditorFontSize)...Double(Typography.maximumEditorFontSize)
                )
                Text("Background and foreground colors are configured in Appearance → Terminal Colors.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Stepper(
                    "Scrollback Limit: \(settings.terminal.scrollbackLimit)",
                    value: $settings.terminal.scrollbackLimit,
                    in: 1_000...100_000,
                    step: 1_000
                )
                .accessibilityLabel("Terminal scrollback limit")

                Picker("Cursor Style", selection: $settings.terminal.cursorStyle) {
                    Text("Block").tag(TerminalCursorStyle.block)
                    Text("Underline").tag(TerminalCursorStyle.underline)
                    Text("Bar").tag(TerminalCursorStyle.bar)
                }
                .accessibilityHint("Applied when SwiftTerm exposes cursor style safely")

                Toggle("Cursor Blink", isOn: $settings.terminal.cursorBlink)
                Toggle("Audible Bell", isOn: $settings.terminal.audibleBell)
                Toggle("Visual Bell", isOn: $settings.terminal.visualBell)
                Toggle("Copy on Selection", isOn: $settings.terminal.copyOnSelection)
                    .disabled(true)
                    .help("SwiftTerm 1.13 does not expose copy-on-selection safely; control disabled.")
            }

            Section("Run Defaults") {
                Text("These apply when a workspace is first opened. Existing workspace Run preferences are not overwritten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Clear Terminal Before Run", isOn: $settings.terminal.clearTerminalBeforeRun)
                Toggle("Reveal Terminal on Run", isOn: $settings.terminal.revealTerminalOnRun)
            }

            Section {
                Button("Restore Terminal Defaults") {
                    settings.restoreDefaults(for: .terminal)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
