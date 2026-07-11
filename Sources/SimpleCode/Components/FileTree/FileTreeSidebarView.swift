import SwiftUI
import UniformTypeIdentifiers

struct FileTreeSidebarView: View {
    @Bindable var workspace: WorkspaceModel
    @State private var hoveredNodeID: FileTreeNodeID?

    private var openFilePaths: Set<String> {
        Set(workspace.openDocuments.sessions.compactMap {
            $0.fileURL?.standardizedFileURL.path
        })
    }

    private var dirtyFilePaths: Set<String> {
        Set(workspace.openDocuments.sessions.compactMap { session in
            guard session.isDirty else { return nil }
            return session.fileURL?.standardizedFileURL.path
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarToolbar

            if workspace.fileTree.isLoadingRoot {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(workspace.fileTree.visibleRows) { row in
                            FileTreeRowView(
                                row: row,
                                workspace: workspace,
                                openFilePaths: openFilePaths,
                                dirtyFilePaths: dirtyFilePaths,
                                isHovered: hoveredNodeID == row.node.id,
                                onHover: { hovering in
                                    hoveredNodeID = hovering ? row.node.id : nil
                                }
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.xSmall)
                    .padding(.vertical, Spacing.xSmall)
                }
                .accessibilityIdentifier("fileTree.sidebar")
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleRootDrop(providers: providers)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .glassPanel(cornerRadius: CornerRadius.panel)
        .shadow(color: .black.opacity(0.16), radius: 22, y: 10)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.panel, style: .continuous))
        .sheet(item: $workspace.pendingRename) { pending in
            RenameSheet(name: Binding(
                get: { workspace.pendingRename?.name ?? pending.name },
                set: { workspace.pendingRename?.name = $0 }
            )) {
                Task {
                    await workspace.rename(item: pending.url, to: workspace.pendingRename?.name ?? pending.name)
                    workspace.pendingRename = nil
                }
            } onCancel: {
                workspace.pendingRename = nil
            }
        }
    }

    private func handleRootDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data, let source = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                await workspace.moveItem(from: source, to: workspace.rootURL)
            }
        }
        return true
    }

    private var sidebarToolbar: some View {
        HStack(spacing: Spacing.xSmall) {
            Text("Files")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button { workspace.beginCreateNewFile() } label: { Image(systemName: "doc.badge.plus") }
                .help("New File")
                .pointingHandCursor()
            Button { workspace.beginCreateNewFolder() } label: { Image(systemName: "folder.badge.plus") }
                .help("New Folder")
                .pointingHandCursor()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.xSmall)
    }
}

private struct FileTreeRowView: View {
    let row: FileTreeVisibleRow
    @Bindable var workspace: WorkspaceModel
    let openFilePaths: Set<String>
    let dirtyFilePaths: Set<String>
    let isHovered: Bool
    let onHover: (Bool) -> Void
    @State private var isDropTarget = false

    private var relativePath: String {
        FileTreeAccessibility.relativePath(for: node.url, workspaceRoot: workspace.rootURL)
    }

    var body: some View {
        if node.isDirectory {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Button {
                        Task { await toggleExpansion() }
                    } label: {
                        Image(systemName: workspace.fileTree.expandedNodeIDs.contains(node.id) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("fileTree.disclosure.\(relativePath)")
                    rowLabel
                }
                if workspace.fileTree.expandedNodeIDs.contains(node.id) {
                    if node.isLoading {
                        ProgressView().controlSize(.small)
                            .padding(.leading, CGFloat(depth + 1) * 12)
                    } else if let error = node.loadError {
                        Label(errorText(error), systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .padding(.leading, CGFloat(depth + 1) * 12)
                    } else {
                        ForEach(node.children ?? []) { child in
                            FileTreeRowView(node: child, workspace: workspace, depth: depth + 1)
                        }
                    }
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
                handleDrop(providers: providers, destination: node.url)
            }
            .background(isDropTarget ? Color.accentColor.opacity(0.15) : Color.clear)
        } else {
            rowLabel
            .accessibilityIdentifier("fileTree.row.\(relativePath)")
            .onDrag { NSItemProvider(object: node.url as NSURL) }
        }
    }

    private func toggleExpansion() async {
        if workspace.fileTree.expandedNodeIDs.contains(node.id) {
            workspace.fileTree.expandedNodeIDs.remove(node.id)
        } else {
            workspace.fileTree.expandedNodeIDs.insert(node.id)
            await workspace.fileTree.loadChildrenIfNeeded(for: node.id)
        }
    }

    private var rowLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .foregroundStyle(node.isDirectory ? Color.accentColor : .secondary)
            Text(node.name)
                .font(.system(size: 12))
                .foregroundStyle(isActiveFile ? Color.accentColor : .primary)
            if node.isSymlink {
                Image(systemName: "link").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .padding(.leading, CGFloat(depth) * 12)
        .contextMenu { contextMenu }
        .tag(node.id)
        .onDrag { NSItemProvider(object: node.url as NSURL) }
    }

    private func handleDrop(providers: [NSItemProvider], destination: URL) -> Bool {
        guard node.isDirectory else { return false }
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data, let source = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                await workspace.moveItem(from: source, to: destination)
            }
        }
        return true
    }

    @ViewBuilder
    private var contextMenu: some View {
        if !node.isDirectory {
            Button("Open") { Task { await workspace.openFile(url: node.url) } }
        }
        Button("New File") {
            workspace.beginCreateNewFile(in: node.isDirectory ? node.url : node.url.deletingLastPathComponent())
        }
        Button("New Folder") {
            workspace.beginCreateNewFolder(in: node.isDirectory ? node.url : node.url.deletingLastPathComponent())
        }
        Divider()
        Button("Rename") {
            workspace.pendingRename = WorkspaceModel.PendingRename(url: node.url, name: node.name)
        }
        Button("Duplicate") { Task { await workspace.duplicate(item: node.url) } }
        Button("Delete", role: .destructive) { workspace.requestDelete(item: node.url, isDirectory: node.isDirectory) }
        Divider()
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.url.path, forType: .string)
        }
        Button("Copy Relative Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(relativePath, forType: .string)
        }
    }
}

enum FileTreeAccessibility {
    static func relativePath(for url: URL, workspaceRoot: URL) -> String {
        let root = workspaceRoot.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == root { return url.lastPathComponent }
        let prefix = root + "/"
        if path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
        return url.lastPathComponent
    }
}

private struct RenameSheet: View {
    @Binding var name: String
    var onRename: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("Rename").font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("fileTree.renameField")
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Rename", action: onRename)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("fileTree.renameConfirm")
            }
        }
        .padding(Spacing.large)
        .frame(width: 360)
        .accessibilityIdentifier("fileTree.renameSheet")
    }
}
