import SwiftUI

struct TerminalSettingsView: View {
    @Bindable var settings: AppSettingsStore

    var body: some View {
        Form {
            Section("Font") {
                Picker("Font Family", selection: $settings.typography.terminalFontFamily) {
                    ForEach(FontCatalog.monospacedFamilies, id: \.self) { family in
                        Text(FontCatalog.displayName(for: family)).tag(family)
                    }
                }
                .pointingHandCursor()
                .accessibilityIdentifier("settings.terminal.fontFamily")

                Stepper(
                    "Font Size: \(Int(settings.typography.terminalFontSize))",
                    value: $settings.typography.terminalFontSize,
                    in: Double(Typography.minimumEditorFontSize)...Double(Typography.maximumEditorFontSize)
                )
                .pointingHandCursor()
                .accessibilityIdentifier("settings.terminal.fontSize")

                Text("Terminal line spacing follows the selected terminal font for reliable cell alignment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Restore Terminal Defaults") {
                    settings.typography.terminalFontFamily = TypographySettings.defaults.terminalFontFamily
                    settings.typography.terminalFontSize = TypographySettings.defaults.terminalFontSize
                }
                .pointingHandCursor()
            }
        }
        .formStyle(.grouped)
        .padding()
        .accessibilityIdentifier("settings.section.terminal")
    }
}
