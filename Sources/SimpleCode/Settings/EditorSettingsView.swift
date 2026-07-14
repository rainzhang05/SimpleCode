import SwiftUI

struct EditorSettingsView: View {
    @Bindable var settings: AppSettingsStore
    @State private var customTabWidth: Int
    @State private var selectedTabWidth: EditorTabWidthChoice

    init(settings: AppSettingsStore) {
        self.settings = settings
        let width = settings.editor.tabWidth
        let selection = EditorTabWidthChoice.selection(for: width)
        _selectedTabWidth = State(initialValue: selection)
        _customTabWidth = State(initialValue: selection == .custom
            ? width
            : EditorTabWidthChoice.defaultCustomWidth)
    }

    var body: some View {
        Form {
            Section("Font") {
                Picker("Font Family", selection: $settings.typography.editorFontFamily) {
                    ForEach(FontCatalog.monospacedFamilies, id: \.self) { family in
                        Text(FontCatalog.displayName(for: family)).tag(family)
                    }
                }
                .pointingHandCursor()
                .accessibilityIdentifier("settings.editor.fontFamily")

                Stepper(
                    "Font Size: \(Int(settings.typography.editorFontSize))",
                    value: $settings.typography.editorFontSize,
                    in: Double(Typography.minimumEditorFontSize)...Double(Typography.maximumEditorFontSize)
                )
                .pointingHandCursor()
                .accessibilityIdentifier("settings.editor.fontSize")

                Toggle("Font Ligatures", isOn: $settings.typography.editorFontLigatures)
                    .pointingHandCursor()
                    .accessibilityIdentifier("settings.editor.fontLigatures")

                Text("func hello() { return 42 }")
                    .font(Font(nsFont: Typography.editorFont(
                        family: settings.typography.editorFontFamily,
                        size: CGFloat(settings.typography.editorFontSize),
                        ligatures: settings.typography.editorFontLigatures
                    )))
                    .padding(.vertical, 4)
                    .accessibilityLabel("Editor font preview")
            }

            Section("Indentation") {
                Picker("Tab Width", selection: tabWidthSelection) {
                    ForEach(EditorTabWidthChoice.options, id: \.self) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .pointingHandCursor()
                .accessibilityIdentifier("settings.editor.tabWidth")
                if selectedTabWidth == .custom {
                    Stepper(
                        "Custom Width: \(customTabWidth)",
                        value: customTabWidthBinding,
                        in: 1...16
                    )
                    .pointingHandCursor()
                    .accessibilityIdentifier("settings.editor.customTabWidth")
                }
                Toggle("Insert Spaces", isOn: $settings.editor.insertSpaces)
                    .pointingHandCursor()
                Toggle("Auto Indent", isOn: $settings.editor.autoIndent)
                    .pointingHandCursor()
                Toggle("Auto-Closing Pairs", isOn: $settings.editor.autoClosingPairs)
                    .pointingHandCursor()
                Toggle("Smart Pair Deletion", isOn: $settings.editor.smartPairDeletion)
                    .pointingHandCursor()
                Toggle("Smart Home", isOn: $settings.editor.smartHome)
                    .pointingHandCursor()
                Toggle("Smart Backspace", isOn: $settings.editor.smartBackspace)
                    .pointingHandCursor()
            }

            Section("Display") {
                Toggle("Word Wrap", isOn: $settings.editor.wordWrap)
                    .pointingHandCursor()
                Toggle("Line Numbers", isOn: $settings.editor.showLineNumbers)
                    .pointingHandCursor()
                    .accessibilityIdentifier("settings.editor.lineNumbers")
                Toggle("Highlight Current Line", isOn: $settings.editor.highlightCurrentLine)
                    .pointingHandCursor()
                Toggle("Show Whitespace", isOn: $settings.editor.showWhitespace)
                    .pointingHandCursor()
                    .accessibilityIdentifier("settings.editor.showWhitespace")
                Toggle("Show Trailing Whitespace", isOn: $settings.editor.showTrailingWhitespace)
                    .pointingHandCursor()
                    .accessibilityIdentifier("settings.editor.showTrailingWhitespace")
                Toggle("Long Line Guide", isOn: $settings.editor.showLongLineGuide)
                    .pointingHandCursor()
                    .accessibilityIdentifier("settings.editor.longLineGuide")
                if settings.editor.showLongLineGuide {
                    Stepper(
                        "Guide Column: \(settings.editor.longLineGuideColumn)",
                        value: $settings.editor.longLineGuideColumn,
                        in: 40...200
                    )
                    .pointingHandCursor()
                    .accessibilityIdentifier("settings.editor.guideColumn")
                }
            }

            Section("Save") {
                Toggle("Trim Trailing Whitespace on Save", isOn: $settings.editor.trimTrailingWhitespaceOnSave)
                    .pointingHandCursor()
                Toggle("Ensure Final Newline on Save", isOn: $settings.editor.ensureFinalNewlineOnSave)
                    .pointingHandCursor()
            }

            Section {
                Button("Restore Editor Defaults") {
                    settings.restoreDefaults(for: .editor)
                    settings.typography.editorFontFamily = TypographySettings.defaults.editorFontFamily
                    settings.typography.editorFontSize = TypographySettings.defaults.editorFontSize
                    settings.typography.editorFontLigatures = TypographySettings.defaults.editorFontLigatures
                    customTabWidth = EditorTabWidthChoice.defaultCustomWidth
                    selectedTabWidth = EditorTabWidthChoice.selection(for: settings.editor.tabWidth)
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
            get: { selectedTabWidth },
            set: { choice in
                if selectedTabWidth == .custom {
                    customTabWidth = settings.editor.tabWidth
                }
                selectedTabWidth = choice
                switch choice {
                case let .preset(width):
                    settings.editor.tabWidth = width
                case .custom:
                    settings.editor.tabWidth = customTabWidth
                }
            }
        )
    }

    private var customTabWidthBinding: Binding<Int> {
        Binding(
            get: { customTabWidth },
            set: {
                customTabWidth = $0
                settings.editor.tabWidth = $0
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
        switch self {
        case let .preset(width): width
        case .custom: Self.defaultCustomWidth
        }
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

private extension Font {
    init(nsFont: NSFont) {
        self.init(nsFont as CTFont)
    }
}
