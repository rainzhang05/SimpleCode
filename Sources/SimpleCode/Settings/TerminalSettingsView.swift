import SwiftUI

struct TerminalSettingsView: View {
    @Bindable var settings: AppSettingsStore

    var body: some View {
        Form {
            Section("Behavior") {
                Stepper(
                    "Scrollback Limit: \(settings.terminal.scrollbackLimit)",
                    value: $settings.terminal.scrollbackLimit,
                    in: 1_000...100_000,
                    step: 1_000
                )
                .accessibilityLabel("Terminal scrollback limit")
                Text("Terminal type is configured in Typography. Colors are configured in Appearance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Restore Terminal Defaults") {
                    settings.restoreDefaults(for: .terminal)
                }
                .pointingHandCursor()
            }
        }
        .formStyle(.grouped)
        .padding()
        .accessibilityIdentifier("settings.section.terminal")
    }
}
