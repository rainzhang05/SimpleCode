import SwiftUI

struct EditorSettingsView: View {
    @Bindable var settings: AppSettingsStore

    var body: some View {
        Form {
            Section("Indentation") {
                Picker("Tab Width", selection: tabWidthSelection) {
                    ForEach(EditorTabWidthChoice.options, id: \.self) { choice in
                        Text(choice.label).tag(choice)
                    }
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
                    .accessibilityIdentifier("settings.editor.lineNumbers")
                Toggle("Highlight Current Line", isOn: $settings.editor.highlightCurrentLine)
                Toggle("Show Whitespace", isOn: $settings.editor.showWhitespace)
                Toggle("Show Trailing Whitespace", isOn: $settings.editor.showTrailingWhitespace)
                Toggle("Long Line Guide", isOn: $settings.editor.showLongLineGuide)
                Stepper(
                    "Guide Column: \(settings.editor.longLineGuideColumn)",
                    value: $settings.editor.longLineGuideColumn,
                    in: 40...200
                )
            }

            Section("Save") {
                Toggle("Trim Trailing Whitespace on Save", isOn: $settings.editor.trimTrailingWhitespaceOnSave)
                Toggle("Ensure Final Newline on Save", isOn: $settings.editor.ensureFinalNewlineOnSave)
            }

            Section {
                Button("Restore Editor Defaults") {
                    settings.restoreDefaults(for: .editor)
                }
                .pointingHandCursor()
            }
        }
        .formStyle(.grouped)
        .padding()
        .accessibilityIdentifier("settings.section.editor")
    }

    private var tabWidthSelection: Binding<EditorTabWidthChoice> {
        Binding(
            get: { EditorTabWidthChoice.selection(for: settings.editor.tabWidth) },
            set: { choice in
                settings.editor.tabWidth = choice.width ?? EditorTabWidthChoice.defaultCustomWidth
            }
        )
    }
}

enum EditorTabWidthChoice: Hashable {
    case preset(Int)
    case custom

    static let options: [EditorTabWidthChoice] = [.preset(2), .preset(4), .preset(8), .custom]
    static let defaultCustomWidth = 3

    static func selection(for width: Int) -> EditorTabWidthChoice {
        options.contains(.preset(width)) ? .preset(width) : .custom
    }

    var width: Int? {
        guard case let .preset(width) = self else { return nil }
        return width
    }

    var label: String {
        switch self {
        case let .preset(width):
            "\(width) spaces"
        case .custom:
            "Custom"
        }
    }
}
