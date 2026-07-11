import Foundation

struct FileTreeNodeState: Identifiable, Equatable {
    let id: FileTreeNodeID
    let name: String
    let url: URL
    let isDirectory: Bool
    let isSymlink: Bool
    var children: [FileTreeNodeState]?
    var isLoading = false
    var loadError: FileTreeLoadError?
}

/// A flattened, visible tree row. Keeping this derived state in the model means
/// SwiftUI does not recursively walk the entire workspace tree during every hover,
/// selection, or document-dirty update.
struct FileTreeVisibleRow: Identifiable, Equatable {
    let node: FileTreeNodeState
    let depth: Int

    var id: FileTreeNodeID { node.id }
}

@MainActor
@Observable
final class FileTreeModel {
    let workspaceRoot: URL
    private(set) var rootChildren: [FileTreeNodeState] = []
    private(set) var visibleRows: [FileTreeVisibleRow] = []
    var expandedNodeIDs: Set<FileTreeNodeID> = [] {
        didSet { rebuildVisibleRows() }
    }
    var selectedNodeID: FileTreeNodeID?
    var activeFileURL: URL?
    /// Source folders are part of the workspace even when their name starts with a
    /// dot. Filtering them made common project configuration disappear unexpectedly.
    var showHiddenFiles = true
    var userExclusions: [String] = []
    private(set) var isLoadingRoot = false

    private let treeService = WorkspaceFileTreeService()

    init(workspaceRoot: URL) {
        self.workspaceRoot = workspaceRoot
    }

    func loadRoot() async {
        isLoadingRoot = true
        let listing = await treeService.listDirectory(
            at: workspaceRoot,
            workspaceRoot: workspaceRoot,
            showHidden: showHiddenFiles,
            userPatterns: userExclusions
        )
        rootChildren = listing.children.map { child in
            FileTreeNodeState(
                id: child.id,
                name: child.name,
                url: child.url,
                isDirectory: child.isDirectory,
                isSymlink: child.isSymlink,
                children: child.isDirectory ? nil : []
            )
        }
        if let error = listing.error, rootChildren.isEmpty {
            rootChildren = [FileTreeNodeState(
                id: FileTreeNodeID(url: workspaceRoot),
                name: workspaceRoot.lastPathComponent,
                url: workspaceRoot,
                isDirectory: true,
                isSymlink: false,
                children: [],
                loadError: error
            )]
        }
        rebuildVisibleRows()
        isLoadingRoot = false
    }

    func refresh() async {
        let preserved = expandedNodeIDs
        await loadRoot()
        expandedNodeIDs = preserved
        // Parents have to be restored before their descendants can be found in the
        // freshly rebuilt tree. Deterministic shallow-to-deep replay also avoids
        // redundant failed lookups for deeply expanded workspaces.
        for id in preserved.sorted(by: { lhs, rhs in
            lhs.path.split(separator: "/").count < rhs.path.split(separator: "/").count
        }) {
            await loadChildrenIfNeeded(for: id)
        }
    }

    func collapseAll() {
        expandedNodeIDs.removeAll()
        clearChildrenRecursively(&rootChildren)
        rebuildVisibleRows()
    }

    func toggleExpansion(for nodeID: FileTreeNodeID) async {
        if expandedNodeIDs.contains(nodeID) {
            expandedNodeIDs.remove(nodeID)
        } else {
            expandedNodeIDs.insert(nodeID)
            await loadChildrenIfNeeded(for: nodeID)
        }
    }

    func loadChildrenIfNeeded(for nodeID: FileTreeNodeID) async {
        guard let node = findNode(id: nodeID) else { return }
        guard node.isDirectory else { return }
        if node.children != nil && node.loadError == nil && !node.isLoading {
            return
        }

        setLoading(true, for: nodeID)
        let listing = await treeService.listDirectory(
            at: node.url,
            workspaceRoot: workspaceRoot,
            showHidden: showHiddenFiles,
            userPatterns: userExclusions
        )
        let children = listing.children.map { child in
            FileTreeNodeState(
                id: child.id,
                name: child.name,
                url: child.url,
                isDirectory: child.isDirectory,
                isSymlink: child.isSymlink,
                children: child.isDirectory ? nil : []
            )
        }
        updateNode(nodeID) { node in
            node.children = children
            node.isLoading = false
            node.loadError = listing.error
        }
    }

    func destinationDirectoryForCreation() -> URL {
        if let selected = selectedNodeID, let node = findNode(id: selected) {
            return node.isDirectory ? node.url : node.url.deletingLastPathComponent()
        }
        return workspaceRoot
    }

    func node(for id: FileTreeNodeID) -> FileTreeNodeState? {
        findNode(id: id)
    }

    private func setLoading(_ loading: Bool, for nodeID: FileTreeNodeID) {
        updateNode(nodeID) { $0.isLoading = loading }
    }

    private func clearChildrenRecursively(_ nodes: inout [FileTreeNodeState]) {
        for index in nodes.indices {
            if var children = nodes[index].children {
                clearChildrenRecursively(&children)
                nodes[index].children = children
            }
            nodes[index].children = nodes[index].isDirectory ? nil : []
        }
    }

    private func findNode(id: FileTreeNodeID) -> FileTreeNodeState? {
        findNode(id: id, in: rootChildren)
    }

    private func findNode(id: FileTreeNodeID, in nodes: [FileTreeNodeState]) -> FileTreeNodeState? {
        for node in nodes {
            if node.id == id { return node }
            if let children = node.children, let found = findNode(id: id, in: children) {
                return found
            }
        }
        return nil
    }

    private func updateNode(_ id: FileTreeNodeID, mutate: (inout FileTreeNodeState) -> Void) {
        _ = updateNode(id: id, in: &rootChildren, mutate: mutate)
        rebuildVisibleRows()
    }

    private func updateNode(id: FileTreeNodeID, in nodes: inout [FileTreeNodeState], mutate: (inout FileTreeNodeState) -> Void) -> Bool {
        for index in nodes.indices {
            if nodes[index].id == id {
                mutate(&nodes[index])
                return true
            }
            if var children = nodes[index].children,
               updateNode(id: id, in: &children, mutate: mutate) {
                nodes[index].children = children
                return true
            }
        }
        return false
    }

    private func rebuildVisibleRows() {
        var rows: [FileTreeVisibleRow] = []
        rows.reserveCapacity(visibleRows.count)
        appendVisibleRows(from: rootChildren, depth: 0, into: &rows)
        visibleRows = rows
    }

    private func appendVisibleRows(
        from nodes: [FileTreeNodeState],
        depth: Int,
        into rows: inout [FileTreeVisibleRow]
    ) {
        for node in nodes {
            rows.append(FileTreeVisibleRow(node: node, depth: depth))
            guard node.isDirectory,
                  expandedNodeIDs.contains(node.id),
                  let children = node.children else { continue }
            appendVisibleRows(from: children, depth: depth + 1, into: &rows)
        }
    }
}
