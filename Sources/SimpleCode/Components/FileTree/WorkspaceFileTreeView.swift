import SwiftUI

/// A shallow, read-only listing of the workspace root.
///
/// Deliberately not recursive and not backed by a background actor: a single-level
/// `contentsOfDirectory` call is cheap enough to run directly on the main actor, and
/// introducing an actor here for work this small would be exactly the premature
/// concurrency decomposition the code-quality rules warn against. Recursive, lazily
/// loaded tree construction (which *would* justify a background actor) is deferred
/// to a later phase, per the architecture report.
struct WorkspaceFileTreeView: View {
    let rootURL: URL

    @State private var entries: [FileTreeEntry] = []
    @State private var loadErrorMessage: String?

    var body: some View {
        Group {
            if let loadErrorMessage {
                VStack(spacing: Spacing.xSmall) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Text(loadErrorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                List(entries) { entry in
                    Label {
                        Text(entry.name)
                            .font(.system(size: 12))
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: entry.isDirectory ? "folder.fill" : "doc.text")
                            .foregroundStyle(entry.isDirectory ? Color.accentColor : .secondary)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .task(id: rootURL) {
            load()
        }
    }

    private func load() {
        do {
            let items = try FileManager.default.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            let mapped = items.map { url -> FileTreeEntry in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                return FileTreeEntry(url: url, isDirectory: isDirectory)
            }
            entries = mapped.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            loadErrorMessage = nil
        } catch {
            entries = []
            loadErrorMessage = "This folder's contents could not be read."
            AppLog.filesystem.error("Failed to list workspace root: \(error.localizedDescription, privacy: .public)")
        }
    }
}
