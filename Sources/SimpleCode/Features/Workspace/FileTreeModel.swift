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

@MainActor
@Observable
final class FileTreeModel {
    let workspaceRoot: URL
    private(set) var rootChildren: [FileTreeNodeState] = []
    var expandedNodeIDs: Set<FileTreeNodeID> = []
    var selectedNodeID: FileTreeNodeID?
    var activeFileURL: URL?
    var showHiddenFiles = false
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
        isLoadingRoot = false
    }

    func refresh() async {
        let preserved = expandedNodeIDs
        await loadRoot()
        expandedNodeIDs = preserved
        for id in preserved {
            await loadChildrenIfNeeded(for: id)
        }
    }

    func collapseAll() {
        expandedNodeIDs.removeAll()
        clearChildrenRecursively(&rootChildren)
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
        if node.children != nil && !(node.children?.isEmpty == true && node.loadError == nil) && !node.isLoading {
            // already loaded unless explicitly empty first pass
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
            nodes[index].children = nil
            if var children = nodes[index].children {
                clearChildrenRecursively(&children)
                nodes[index].children = children
            }
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
}
