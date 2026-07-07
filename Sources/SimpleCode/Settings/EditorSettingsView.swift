import SwiftUI

struct EditorSettingsView: View {
    @Bindable var settings: AppSettingsStore

    private let tabWidthOptions = [2, 4, 8]

    var body: some View {
        Form {
            Section("Indentation") {
                Picker("Tab Width", selection: $settings.editor.tabWidth) {
                    ForEach(tabWidthOptions, id: \.self) { width in
                        Text("\(width) spaces").tag(width)
                    }
                    Text("Custom").tag(settings.editor.tabWidth)
                }
                Stepper(
                    "Custom Width: \(settings.editor.tabWidth)",
                    value: $settings.editor.tabWidth,
                    in: 1...16
                )
                Toggle("Insert Spaces", isOn: $settings.editor.insertSpaces)
                Toggle("Auto Indent", isOn: $settings.editor.autoIndent)
                Toggle("Auto-Closing Pairs", isOn: $settings.editor.autoClosingPairs)
                Toggle("Smart Pair Deletion", isOn: $settings.editor.smartPairDeletion)
                Toggle("Smart Home", isOn: $settings.editor.smartHome)
                Toggle("Smart Backspace", isOn: $settings.editor.smartBackspace)
            }

            Section("Display") {
                Toggle("Word Wrap", isOn: $settings.editor.wordWrap)
                Toggle("Line Numbers", isOn: $settings.editor.showLineNumbers)
                Toggle("Highlight Current Line", isOn: $settings.editor.highlightCurrentLine)
                Toggle("Show Whitespace", isOn: $settings.editor.showWhitespace)
                Toggle("Show Trailing Whitespace", isOn: $settings.editor.showTrailingWhitespace)
                Toggle("Long Line Guide", isOn: $settings.editor.showLongLineGuide)
                Stepper(
                    "Guide Column: \(settings.editor.longLineGuideColumn)",
                    value: $settings.editor.longLineGuideColumn,
                    in: 40...200
                )
                Toggle("Automatic Syntax Highlighting", isOn: $settings.editor.automaticSyntaxHighlighting)
            }

            Section("Session & Save") {
                Toggle("Restore Open Editors", isOn: $settings.editor.restoreOpenEditors)
                Toggle("Trim Trailing Whitespace on Save", isOn: $settings.editor.trimTrailingWhitespaceOnSave)
                Toggle("Ensure Final Newline on Save", isOn: $settings.editor.ensureFinalNewlineOnSave)
            }

            Section {
                Button("Restore Editor Defaults") {
                    settings.restoreDefaults(for: .editor)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
