import Foundation

struct FileTreeNodeID: Hashable, Sendable {
    let path: String

    init(url: URL) {
        self.path = url.path
    }

    var url: URL { URL(fileURLWithPath: path) }
}

struct FileTreeChild: Identifiable, Equatable, Sendable {
    let id: FileTreeNodeID
    let name: String
    let url: URL
    let isDirectory: Bool
    let isSymlink: Bool
    let isPackage: Bool
}

enum FileTreeLoadError: Equatable, Sendable {
    case permissionDenied
    case unreadable(String)
}

struct FileTreeDirectoryListing: Sendable {
    let url: URL
    let children: [FileTreeChild]
    let error: FileTreeLoadError?
}

actor WorkspaceFileTreeService {
    func listDirectory(
        at url: URL,
        workspaceRoot: URL,
        userPatterns: [String] = []
    ) -> FileTreeDirectoryListing {
        let rootPath = workspaceRoot.path
        let rootPathPrefix = rootPath + "/"
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isPackageKey
        ]

        do {
            let items = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: []
            )

            var children: [FileTreeChild] = []
            children.reserveCapacity(items.count)
            let keysSet = Set(keys)
            for item in items {
                let values = try? item.resourceValues(forKeys: keysSet)
                let isDirectory = values?.isDirectory ?? false
                let isSymlink = values?.isSymbolicLink ?? false
                let name = item.lastPathComponent
                if isDirectory && !userPatterns.isEmpty {
                    let itemPath = item.path
                    let relativePath = itemPath.hasPrefix(rootPathPrefix)
                        ? String(itemPath.dropFirst(rootPathPrefix.count))
                        : name

                    if WorkspaceTreeExclusions.shouldExclude(
                       directoryName: name,
                       relativePath: relativePath,
                       isWorkspaceRoot: false,
                       userPatterns: userPatterns
                    ) {
                        continue
                    }
                }

                children.append(FileTreeChild(
                    id: FileTreeNodeID(url: item),
                    name: name,
                    url: item,
                    isDirectory: isDirectory,
                    isSymlink: isSymlink,
                    isPackage: values?.isPackage ?? false
                ))
            }

            children.sort { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

            return FileTreeDirectoryListing(url: url, children: children, error: nil)
        } catch {
            let ns = error as NSError
            if ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoPermissionError {
                return FileTreeDirectoryListing(url: url, children: [], error: .permissionDenied)
            }
            return FileTreeDirectoryListing(url: url, children: [], error: .unreadable(error.localizedDescription))
        }
    }
}
