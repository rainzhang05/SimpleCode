import Foundation
import Testing
@testable import SimpleCode

struct GitURLParserTests {
    @Test func httpsURL() {
        let result = GitURLParser.parse("https://github.com/owner/repository.git")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success")
            return
        }
        #expect(parsed.derivedFolderName == "repository")
    }

    @Test func sshURL() {
        let result = GitURLParser.parse("ssh://git@github.com/owner/repository.git")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success")
            return
        }
        #expect(parsed.derivedFolderName == "repository")
    }

    @Test func scpLikeSSH() {
        let result = GitURLParser.parse("git@github.com:owner/repository.git")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success")
            return
        }
        #expect(parsed.derivedFolderName == "repository")
    }

    @Test func trailingGitStripped() {
        #expect(GitURLParser.deriveFolderName(from: "https://example.com/foo.git/") == "foo")
    }

    @Test func trailingSlash() {
        #expect(GitURLParser.deriveFolderName(from: "https://example.com/foo/") == "foo")
    }

    @Test func emptyRepositoryNameRejected() {
        let result = GitURLParser.parse("https://github.com/")
        #expect(result.isFailure)
    }

    @Test func newlineRejected() {
        let result = GitURLParser.parse("https://github.com/a\nb.git")
        #expect(result.isFailure)
    }

    @Test func embeddedCredentialRedaction() {
        let result = GitURLParser.parse("https://user:token@github.com/owner/repo.git")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success")
            return
        }
        #expect(parsed.hadEmbeddedCredentials)
        #expect(!parsed.normalizedURL.contains("token"))
    }

    @Test func destinationNameDerivation() {
        #expect(GitURLParser.deriveFolderName(from: "git@host.com:org/project.git") == "project")
    }
}

private extension Result {
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}
