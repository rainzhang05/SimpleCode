import SwiftUI
import UniformTypeIdentifiers

struct FileTreeSidebarView: View {
    @Bindable var workspace: WorkspaceModel
    @State private var resizeStartWidth: CGFloat?
    @State private var isResizeHandleHovered = false

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
        let openFilePaths = openFilePaths
        let dirtyFilePaths = dirtyFilePaths

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
                                dirtyFilePaths: dirtyFilePaths
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
        .overlay(alignment: .trailing) {
            resizeHandle
        }
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

    private var resizeHandle: some View {
        NativeResizeHandle(
            axis: .horizontal,
            accessibilityLabel: "Resize Files Sidebar",
            accessibilityIdentifier: "fileTree.resizeHandle",
            accessibilityValue: "\(Int(workspace.sidebarWidth)) points"
        ) { translation in
            let startWidth = resizeStartWidth ?? workspace.sidebarWidth
            if resizeStartWidth == nil { resizeStartWidth = startWidth }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                workspace.sidebarWidth = startWidth + translation
            }
        } onEnd: {
            resizeStartWidth = nil
        } onIncrement: {
            workspace.sidebarWidth += 16
        } onDecrement: {
            workspace.sidebarWidth -= 16
        }
            .frame(width: 14)
            .contentShape(Rectangle())
            .overlay {
                Capsule()
                    .fill(.primary.opacity(isResizeHandleHovered ? 0.34 : 0.14))
                    .frame(width: 2, height: 32)
            }
            .onHover { isResizeHandleHovered = $0 }
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
    @State private var isHovered = false
    @State private var isDropTarget = false

    private var node: FileTreeNodeState { row.node }

    private var relativePath: String {
        FileTreeAccessibility.relativePath(for: node.url, workspaceRoot: workspace.rootURL)
    }

    var body: some View {
        HStack(spacing: Spacing.xSmall) {
            disclosure

            Image(systemName: iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 16)

            Text(node.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(textColor)

            if node.isSymlink {
                Image(systemName: "link")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Spacing.xSmall)

            if isDirty {
                Circle()
                    .fill(.orange)
                    .frame(width: 6, height: 6)
                    .help("Unsaved changes")
            } else if isOpen {
                Circle()
                    .stroke(ColorRole.chromeAccent.opacity(0.5), lineWidth: 1)
                    .frame(width: 6, height: 6)
                    .help("Open")
            }
        }
        .frame(height: 28)
        .padding(.leading, CGFloat(row.depth) * 16 + Spacing.xSmall)
        .padding(.trailing, Spacing.xSmall)
        .contentShape(RoundedRectangle(cornerRadius: CornerRadius.control, style: .continuous))
        .background(rowBackground, in: RoundedRectangle(cornerRadius: CornerRadius.control, style: .continuous))
        .onHover { isHovered = $0 }
        .onTapGesture(count: 1, perform: activateRow)
        .contextMenu { contextMenu }
        .onDrag { NSItemProvider(object: node.url as NSURL) }
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            handleDrop(providers: providers, destination: node.url)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(relativePath)
        .accessibilityIdentifier("fileTree.row.\(relativePath)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { activateRow() }
    }

    @ViewBuilder
    private var disclosure: some View {
        if node.isDirectory {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 14, height: 14)
                .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                .accessibilityIdentifier("fileTree.disclosure.\(relativePath)")
        } else {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 14, height: 14)
                .hidden()
        }
    }

    private var rowBackground: Color {
        if isDropTarget { return ColorRole.chromeAccent.opacity(0.24) }
        if isSelected { return ColorRole.chromeAccent }
        if isActiveFile { return ColorRole.chromeAccent.opacity(0.16) }
        if isHovered { return ColorRole.chromeAccent.opacity(0.09) }
        return .clear
    }

    private var textColor: Color {
        if isSelected { return .white }
        if isActiveFile { return ColorRole.chromeAccent }
        return .primary
    }

    private var iconColor: Color {
        if isSelected { return .white.opacity(0.92) }
        if node.isDirectory { return ColorRole.chromeAccent }
        return .secondary
    }

    private var iconName: String {
        if node.isDirectory { return isExpanded ? "folder.fill" : "folder" }
        if node.name.hasSuffix(".swift") { return "swift" }
        if node.name.hasSuffix(".md") { return "doc.richtext" }
        if node.name.hasSuffix(".json") { return "curlybraces" }
        return "doc.text"
    }

    private var isExpanded: Bool {
        workspace.fileTree.expandedNodeIDs.contains(node.id)
    }

    private var isSelected: Bool {
        workspace.fileTree.selectedNodeID == node.id
    }

    private var isActiveFile: Bool {
        guard let active = workspace.fileTree.activeFileURL else { return false }
        return active.standardizedFileURL == node.url.standardizedFileURL
    }

    private var isOpen: Bool {
        openFilePaths.contains(node.url.standardizedFileURL.path)
    }

    private var isDirty: Bool {
        dirtyFilePaths.contains(node.url.standardizedFileURL.path)
    }

    private func activateRow() {
        workspace.fileTree.selectedNodeID = node.id
        if node.isDirectory {
            Task { await toggleExpansion() }
        } else {
            Task { await workspace.openFile(url: node.url) }
        }
    }

    private func toggleExpansion() async {
        await workspace.fileTree.toggleExpansion(for: node.id)
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
                    .pointingHandCursor()
                Button("Rename", action: onRename)
                    .keyboardShortcut(.defaultAction)
                    .pointingHandCursor()
                    .accessibilityIdentifier("fileTree.renameConfirm")
            }
        }
        .padding(Spacing.large)
        .frame(width: 360)
        .accessibilityIdentifier("fileTree.renameSheet")
    }
}
