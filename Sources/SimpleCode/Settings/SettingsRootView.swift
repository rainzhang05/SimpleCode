import SwiftUI

struct SettingsRootView: View {
    @Bindable var settings: AppSettingsStore

    var body: some View {
        TabView {
            AppearanceSettingsView(settings: settings)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            TypographySettingsView(settings: settings)
                .tabItem { Label("Typography", systemImage: "textformat") }
            EditorSettingsView(settings: settings)
                .tabItem { Label("Editor", systemImage: "chevron.left.forwardslash.chevron.right") }
            FilesSettingsView(settings: settings)
                .tabItem { Label("Files", systemImage: "folder") }
            TerminalSettingsView(settings: settings)
                .tabItem { Label("Terminal", systemImage: "terminal") }
        }
        .frame(minWidth: 520, minHeight: 420)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.root")
    }
}
