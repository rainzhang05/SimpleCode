import SwiftUI

struct FilesSettingsView: View {
    @Bindable var settings: AppSettingsStore
    @State private var newExclusion = ""

    var body: some View {
        Form {
            Section("File Tree") {
                Toggle("Show Hidden Files", isOn: $settings.files.showHiddenFiles)
                Toggle("Confirm Before Moving to Trash", isOn: $settings.files.confirmBeforeTrash)
            }

            Section("Excluded Directories") {
                Text("Patterns: exact name, * wildcard, or path/name (e.g. vendor/*/cache)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(settings.files.userExclusions, id: \.self) { pattern in
                    HStack {
                        Text(pattern)
                        Spacer()
                        Button(role: .destructive) {
                            settings.files.userExclusions.removeAll { $0 == pattern }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    TextField("Add pattern", text: $newExclusion)
                        .accessibilityLabel("New exclusion pattern")
                    Button("Add") {
                        let trimmed = newExclusion.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, ExclusionPatternValidator.isValid(trimmed) else { return }
                        if !settings.files.userExclusions.contains(trimmed) {
                            settings.files.userExclusions.append(trimmed)
                        }
                        newExclusion = ""
                    }
                    .disabled(!ExclusionPatternValidator.isValid(newExclusion.trimmingCharacters(in: .whitespacesAndNewlines)))
                }

                Button("Reset Exclusions") {
                    settings.files.userExclusions = []
                }
            }

            Section("New Files") {
                Picker("Default Encoding", selection: $settings.files.defaultEncoding) {
                    ForEach([TextEncodingMode.utf8, .utf8WithBOM, .utf16LittleEndian, .utf16BigEndian, .isoLatin1], id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Picker("Default Line Endings", selection: $settings.files.defaultLineEnding) {
                    ForEach([LineEndingMode.lf, .crlf, .cr], id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            Section("Workspaces") {
                Toggle("Confirm Before Opening Large Files", isOn: $settings.files.confirmBeforeOpeningLargeFiles)
                Toggle("Restore Recent Workspaces", isOn: $settings.files.restoreRecentWorkspaces)
                Stepper(
                    "Maximum Recent: \(settings.files.maximumRecentWorkspaceCount)",
                    value: $settings.files.maximumRecentWorkspaceCount,
                    in: 1...50
                )
            }

            Section {
                Button("Restore Files Defaults") {
                    settings.restoreDefaults(for: .files)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

enum ExclusionPatternValidator {
    static func isValid(_ pattern: String) -> Bool {
        guard !pattern.isEmpty, !pattern.contains("..") else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "*-_./"))
        return pattern.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
