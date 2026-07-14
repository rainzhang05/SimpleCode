import SwiftUI

struct TypographySettingsView: View {
    @Bindable var settings: AppSettingsStore

    var body: some View {
        Form {
            Section("Editor") {
                Picker("Font Family", selection: $settings.typography.editorFontFamily) {
                    ForEach(FontCatalog.monospacedFamilies, id: \.self) { family in
                        Text(FontCatalog.displayName(for: family)).tag(family)
                    }
                }
                .pointingHandCursor()
                .accessibilityLabel("Editor font family")

                Stepper(
                    "Font Size: \(Int(settings.typography.editorFontSize))",
                    value: $settings.typography.editorFontSize,
                    in: Double(Typography.minimumEditorFontSize)...Double(Typography.maximumEditorFontSize)
                )
                .pointingHandCursor()
                .accessibilityIdentifier("settings.typography.editorFontSize")

                Toggle("Font Ligatures", isOn: $settings.typography.editorFontLigatures)
                    .pointingHandCursor()

                Text("func hello() { return 42 }")
                    .font(Font(nsFont: Typography.editorFont(
                        family: settings.typography.editorFontFamily,
                        size: CGFloat(settings.typography.editorFontSize),
                        ligatures: settings.typography.editorFontLigatures
                    )))
                    .padding(.vertical, 4)
                    .accessibilityLabel("Editor font preview")
            }

            Section("Terminal") {
                Picker("Font Family", selection: $settings.typography.terminalFontFamily) {
                    ForEach(FontCatalog.monospacedFamilies, id: \.self) { family in
                        Text(FontCatalog.displayName(for: family)).tag(family)
                    }
                }
                .pointingHandCursor()

                Stepper(
                    "Font Size: \(Int(settings.typography.terminalFontSize))",
                    value: $settings.typography.terminalFontSize,
                    in: Double(Typography.minimumEditorFontSize)...Double(Typography.maximumEditorFontSize)
                )
                .pointingHandCursor()

                Text("Terminal line spacing follows the selected terminal font for reliable cell alignment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Restore Typography Defaults") {
                    settings.restoreDefaults(for: .typography)
                }
                .pointingHandCursor()
            }
        }
        .formStyle(.grouped)
        .padding()
        .accessibilityIdentifier("settings.section.typography")
    }
}

private extension Font {
    init(nsFont: NSFont) {
        self.init(nsFont as CTFont)
    }
}
