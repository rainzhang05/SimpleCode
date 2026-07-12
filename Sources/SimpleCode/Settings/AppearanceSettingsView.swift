import SwiftUI

struct AppearanceSettingsView: View {
    @Bindable var settings: AppSettingsStore
    @State private var editingDark = false

    var body: some View {
        Form {
            Section("Editor Colors") {
                Picker("Appearance", selection: $editingDark) {
                    Text("Light").tag(false)
                    Text("Dark").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Color appearance to edit")

                colorRow("Background", pair: \.editorBackground)
                colorRow("Foreground", pair: \.editorForeground)
                colorRow("Current Line", pair: \.editorCurrentLine)
                colorRow("Selection", pair: \.editorSelection)
                colorRow("Gutter", pair: \.gutterBackground)
                colorRow("Line Numbers", pair: \.lineNumber)
                colorRow("Active Line Number", pair: \.activeLineNumber)
                colorRow("Long Line Guide", pair: \.longLineGuide)
                colorRow("Whitespace", pair: \.whitespaceMarker)
            }

            Section("Terminal Colors") {
                colorRow("Background", pair: \.terminalBackground)
                colorRow("Foreground", pair: \.terminalForeground)
            }

            Section("Syntax Colors") {
                syntaxColorRow("Keyword", keyPath: \.keyword)
                syntaxColorRow("Control Flow", keyPath: \.controlFlow)
                syntaxColorRow("Type", keyPath: \.type)
                syntaxColorRow("Function", keyPath: \.function)
                syntaxColorRow("Variable", keyPath: \.variable)
                syntaxColorRow("String", keyPath: \.string)
                syntaxColorRow("Number", keyPath: \.number)
                syntaxColorRow("Comment", keyPath: \.comment)
                syntaxColorRow("Operator", keyPath: \.operator)
                syntaxColorRow("Punctuation", keyPath: \.punctuation)
                syntaxColorRow("Preprocessor", keyPath: \.preprocessor)
                syntaxColorRow("Attribute", keyPath: \.attribute)
                syntaxColorRow("Label", keyPath: \.label)
                syntaxColorRow("Constant", keyPath: \.constant)
                syntaxColorRow("Invalid", keyPath: \.invalid)

                Button("Reset Syntax Palette") {
                    settings.resetSyntaxPalette()
                }
                .pointingHandCursor()
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

    private func colorRow(_ title: String, pair: WritableKeyPath<AppearanceSettings, StoredColorPair>) -> some View {
        ColorSettingRow(
            title: title,
            color: editingDark ? settings.appearance[keyPath: pair].dark : settings.appearance[keyPath: pair].light,
            onChange: { newColor in
                if editingDark {
                    settings.appearance[keyPath: pair].dark = newColor
                } else {
                    settings.appearance[keyPath: pair].light = newColor
                }
            }
        )
    }

    private func syntaxColorRow(_ title: String, keyPath: WritableKeyPath<SyntaxPaletteSettings, StoredColorPair>) -> some View {
        ColorSettingRow(
            title: title,
            color: editingDark ? settings.appearance.syntaxPalette[keyPath: keyPath].dark : settings.appearance.syntaxPalette[keyPath: keyPath].light,
            onChange: { newColor in
                if editingDark {
                    settings.appearance.syntaxPalette[keyPath: keyPath].dark = newColor
                } else {
                    settings.appearance.syntaxPalette[keyPath: keyPath].light = newColor
                }
            }
        )
    }
}

private struct ColorSettingRow: View {
    let title: String
    let color: StoredColor
    let onChange: (StoredColor) -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            ColorPicker("", selection: Binding(
                get: { color.swiftUIColor },
                set: { picked in
                    onChange(StoredColor(nsColor: NSColor(picked)))
                }
            ), supportsOpacity: true)
            .labelsHidden()
            .accessibilityLabel("\(title) color")
        }
    }
}
