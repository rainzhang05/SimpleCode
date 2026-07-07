import Foundation
import Testing
@testable import SimpleCode

struct GitCloneInvocationTests {
    @Test func correctExecutableAndArguments() {
        let dest = URL(fileURLWithPath: "/tmp/my-repo", isDirectory: true)
        let config = GitCloneInvocation.makeConfiguration(
            gitExecutablePath: "/usr/bin/git",
            repositoryURL: "https://github.com/example/repo.git",
            destinationURL: dest
        )
        #expect(config.executableURL.path == "/usr/bin/git")
        #expect(config.arguments == [
            "clone", "--progress", "--",
            "https://github.com/example/repo.git",
            "/tmp/my-repo"
        ])
        #expect(!config.arguments.contains("/usr/bin/git"))
    }

    @Test func destinationWithSpacesAndMetacharacters() {
        let dest = URL(fileURLWithPath: "/tmp/my (repo) & 'quotes'/café", isDirectory: true)
        let config = GitCloneInvocation.makeConfiguration(
            gitExecutablePath: "/opt/homebrew/bin/git",
            repositoryURL: "file:///tmp/source.git",
            destinationURL: dest
        )
        #expect(config.arguments.last == "/tmp/my (repo) & 'quotes'/café")
        #expect(config.arguments[3] == "file:///tmp/source.git")
    }

    @Test func repositoryWithLeadingHyphen() {
        let dest = URL(fileURLWithPath: "/tmp/dest", isDirectory: true)
        let config = GitCloneInvocation.makeConfiguration(
            gitExecutablePath: "/usr/bin/git",
            repositoryURL: "-weird-repo",
            destinationURL: dest
        )
        #expect(config.arguments[3] == "-weird-repo")
        #expect(config.arguments[2] == "--")
    }

    @Test func unicodePaths() {
        let dest = URL(fileURLWithPath: "/tmp/日本語フォルダ", isDirectory: true)
        let config = GitCloneInvocation.makeConfiguration(
            gitExecutablePath: "/usr/bin/git",
            repositoryURL: "/tmp/源.git",
            destinationURL: dest
        )
        #expect(config.arguments.last?.contains("日本語") == true)
        #expect(config.arguments[3].contains("源"))
    }
}
