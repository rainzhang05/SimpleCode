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

/// Monotonic identity for the exclusion rules captured by an asynchronous tree
/// load. A result may only commit when its captured generation is still current.
struct FileTreeExclusionGeneration: Equatable, Sendable {
    private var value: UInt = 0

    mutating func advance() {
        value &+= 1
    }

    func permitsCommit(from captured: Self) -> Bool {
        self == captured
    }
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
    /// Dotfiles are always part of the workspace. Only explicit user exclusions
    /// filter directories from the tree.
    private(set) var userExclusions: [String]
    private(set) var isLoadingRoot = false

    private let treeService = WorkspaceFileTreeService()
    private var exclusionGeneration = FileTreeExclusionGeneration()
    private var nextLoadRequestID: UInt = 0
    private var activeRootRequestID: UInt?
    private var activeChildRequestIDs: [FileTreeNodeID: UInt] = [:]

    init(workspaceRoot: URL, userExclusions: [String] = []) {
        self.workspaceRoot = workspaceRoot
        self.userExclusions = userExclusions
    }

    /// Applies a new exclusion snapshot and reports whether a refresh is needed.
    @discardableResult
    func applyUserExclusions(_ exclusions: [String]) -> Bool {
        guard exclusions != userExclusions else { return false }
        userExclusions = exclusions
        exclusionGeneration.advance()
        return true
    }

    func loadRoot() async {
        _ = await loadRoot(
            userPatterns: userExclusions,
            generation: exclusionGeneration
        )
    }

    private func loadRoot(
        userPatterns: [String],
        generation: FileTreeExclusionGeneration
    ) async -> Bool {
        let requestID = makeLoadRequestID()
        activeRootRequestID = requestID
        activeChildRequestIDs.removeAll()
        isLoadingRoot = true
        let listing = await treeService.listDirectory(
            at: workspaceRoot,
            workspaceRoot: workspaceRoot,
            userPatterns: userPatterns
        )
        guard activeRootRequestID == requestID else { return false }
        guard exclusionGeneration.permitsCommit(from: generation) else {
            activeRootRequestID = nil
            isLoadingRoot = false
            return false
        }
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
        activeRootRequestID = nil
        isLoadingRoot = false
        return true
    }

    func refresh() async {
        // A settings observation can run while directory I/O is suspended. Use one
        // immutable exclusion snapshot for the complete root-and-descendant replay.
        let userPatterns = userExclusions
        let generation = exclusionGeneration
        let preserved = expandedNodeIDs
        guard await loadRoot(userPatterns: userPatterns, generation: generation) else { return }
        expandedNodeIDs = preserved
        // Parents have to be restored before their descendants can be found in the
        // freshly rebuilt tree. Deterministic shallow-to-deep replay also avoids
        // redundant failed lookups for deeply expanded workspaces.
        for id in preserved.sorted(by: { lhs, rhs in
            lhs.path.split(separator: "/").count < rhs.path.split(separator: "/").count
        }) {
            guard exclusionGeneration.permitsCommit(from: generation) else { return }
            await loadChildrenIfNeeded(
                for: id,
                userPatterns: userPatterns,
                generation: generation
            )
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
        await loadChildrenIfNeeded(
            for: nodeID,
            userPatterns: userExclusions,
            generation: exclusionGeneration
        )
    }

    private func loadChildrenIfNeeded(
        for nodeID: FileTreeNodeID,
        userPatterns: [String],
        generation: FileTreeExclusionGeneration
    ) async {
        guard exclusionGeneration.permitsCommit(from: generation) else { return }
        guard let node = findNode(id: nodeID) else { return }
        guard node.isDirectory else { return }
        if node.children != nil && node.loadError == nil && !node.isLoading {
            return
        }

        let requestID = makeLoadRequestID()
        activeChildRequestIDs[nodeID] = requestID
        setLoading(true, for: nodeID)
        let listing = await treeService.listDirectory(
            at: node.url,
            workspaceRoot: workspaceRoot,
            userPatterns: userPatterns
        )
        guard activeChildRequestIDs[nodeID] == requestID else { return }
        activeChildRequestIDs[nodeID] = nil
        guard exclusionGeneration.permitsCommit(from: generation) else {
            setLoading(false, for: nodeID)
            return
        }
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

    private func makeLoadRequestID() -> UInt {
        nextLoadRequestID &+= 1
        return nextLoadRequestID
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
