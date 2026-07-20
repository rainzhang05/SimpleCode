import SwiftUI

/// "Create a New Folder" workflow: a name field plus a native folder picker for the
/// parent location, then an actual `FileManager` directory creation — a real,
/// working flow, not a placeholder.
struct NewFolderSheet: View {
    var onCreate: (URL) -> Void
    var onCancel: () -> Void

    @State private var folderName: String = "New Folder"
    @State private var parentURL: URL?
    @State private var isChoosingLocation = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("Create a New Folder")
                .font(.headline)

            TextField("Folder Name", text: $folderName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text(parentURL?.path ?? "Choose a location…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose…") {
                    isChoosingLocation = true
                }
                .pointingHandCursor()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .pointingHandCursor()
                Button("Create") {
                    create()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .pointingHandCursor()
                .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parentURL == nil)
            }
        }
        .padding(Spacing.large)
        .frame(width: 420)
        .fileImporter(isPresented: $isChoosingLocation, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                parentURL = url
                errorMessage = nil
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func create() {
        guard let parentURL else { return }
        let trimmedName = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let validationError = Self.validateFolderName(trimmedName) {
            errorMessage = validationError
            return
        }

        let destination = parentURL.appending(path: trimmedName)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            onCreate(destination)
        } catch {
            errorMessage = "Couldn't create that folder: \(error.localizedDescription)"
            AppLog.filesystem.error("Failed to create new workspace folder: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func validateFolderName(_ name: String) -> String? {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\")
        if name.rangeOfCharacter(from: invalidCharacters) != nil {
            return "Folder names cannot contain /, :, or \\."
        }
        if name == "." || name == ".." {
            return "That folder name is not allowed."
        }
        return nil
    }
}
