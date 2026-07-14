import SwiftUI

struct AppearanceSettingsView: View {
    @Bindable var settings: AppSettingsStore

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $settings.appearance.mode) {
                    ForEach(AppAppearanceMode.allCases, id: \.self) { mode in
                        Text(label(for: mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .pointingHandCursor()
                .accessibilityIdentifier("settings.appearance.mode")
            }

            Section {
                Button("Restore Appearance Defaults") {
                    settings.restoreDefaults(for: .appearance)
                }
                .pointingHandCursor()
            }
        }
        .formStyle(.grouped)
        .padding()
        .accessibilityIdentifier("settings.section.appearance")
    }

    private func label(for mode: AppAppearanceMode) -> String {
        switch mode {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}
