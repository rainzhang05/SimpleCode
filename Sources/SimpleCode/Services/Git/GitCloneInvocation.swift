import Foundation

/// Builds a direct `Process` invocation for `git clone` without shell interpolation.
enum GitCloneInvocation {
    struct Configuration: Equatable, Sendable {
        let executableURL: URL
        let arguments: [String]
        let currentDirectoryURL: URL
    }

    static func makeConfiguration(
        gitExecutablePath: String,
        repositoryURL: String,
        destinationURL: URL
    ) -> Configuration {
        let parent = destinationURL.deletingLastPathComponent()
        return Configuration(
            executableURL: URL(fileURLWithPath: gitExecutablePath),
            arguments: ["clone", "--progress", "--", repositoryURL, destinationURL.path],
            currentDirectoryURL: parent
        )
    }
}
