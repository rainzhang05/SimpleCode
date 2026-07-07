import Foundation

/// Directory exclusion rules for workspace tree traversal.
enum WorkspaceTreeExclusions {
    static let defaultDirectoryNames: Set<String> = [
        ".git", ".svn", ".hg",
        "node_modules", ".build", "build", "dist", "DerivedData",
        ".venv", "venv", "__pycache__", ".idea"
    ]

    static func shouldExclude(
        directoryName: String,
        relativePath: String,
        isWorkspaceRoot: Bool,
        userPatterns: [String] = []
    ) -> Bool {
        guard !isWorkspaceRoot else { return false }
        if defaultDirectoryNames.contains(directoryName) { return true }
        return userPatterns.contains { matches(pattern: $0, directoryName: directoryName, relativePath: relativePath) }
    }

    /// Legacy API used by existing tests.
    static func shouldExclude(directoryName: String, isWorkspaceRoot: Bool) -> Bool {
        shouldExclude(directoryName: directoryName, relativePath: directoryName, isWorkspaceRoot: isWorkspaceRoot)
    }

    private static func matches(pattern: String, directoryName: String, relativePath: String) -> Bool {
        if pattern.contains("/") || pattern.contains("*") {
            return fnmatch(pattern, relativePath, FNM_PATHNAME) == 0
                || fnmatch(pattern, directoryName, 0) == 0
        }
        return pattern == directoryName
    }
}
