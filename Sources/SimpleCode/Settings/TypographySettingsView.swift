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
                .accessibilityLabel("Editor font family")

                Stepper(
                    "Font Size: \(Int(settings.typography.editorFontSize))",
                    value: $settings.typography.editorFontSize,
                    in: Double(Typography.minimumEditorFontSize)...Double(Typography.maximumEditorFontSize)
                )

                Slider(
                    value: $settings.typography.editorLineHeight,
                    in: 1.0...2.5,
                    step: 0.05
                ) {
                    Text("Line Height")
                }
                .accessibilityLabel("Editor line height")

                Toggle("Font Ligatures", isOn: $settings.typography.editorFontLigatures)

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

                Stepper(
                    "Font Size: \(Int(settings.typography.terminalFontSize))",
                    value: $settings.typography.terminalFontSize,
                    in: Double(Typography.minimumEditorFontSize)...Double(Typography.maximumEditorFontSize)
                )

                Slider(
                    value: $settings.typography.terminalLineSpacing,
                    in: 1.0...2.0,
                    step: 0.05
                ) {
                    Text("Line Spacing")
                }
                .accessibilityLabel("Terminal line spacing")
            }

            Section {
                Button("Restore Typography Defaults") {
                    settings.restoreDefaults(for: .typography)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private extension Font {
    init(nsFont: NSFont) {
        self.init(nsFont as CTFont)
    }
}
