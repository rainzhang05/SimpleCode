import SwiftUI

struct FilesSettingsView: View {
    @Bindable var settings: AppSettingsStore
    @State private var newExclusion = ""

    var body: some View {
        Form {
            Section("File Tree") {
                Text("Hidden files and folders are always shown in the workspace tree.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        .pointingHandCursor()
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
                    .pointingHandCursor()
                }

                Button("Reset Exclusions") {
                    settings.files.userExclusions = []
                }
                .pointingHandCursor()
            }
        }
        .formStyle(.grouped)
        .padding()
        .accessibilityIdentifier("settings.section.files")
    }
}

enum ExclusionPatternValidator {
    static func isValid(_ pattern: String) -> Bool {
        guard !pattern.isEmpty, !pattern.contains("..") else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "*-_./"))
        return pattern.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
