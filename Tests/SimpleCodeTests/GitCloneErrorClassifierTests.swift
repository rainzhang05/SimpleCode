import Foundation
import Testing
@testable import SimpleCode

struct GitCloneErrorClassifierTests {
    @Test func httpsAuthenticationFailure() {
        let error = GitCloneErrorClassifier.classify(
            sanitizedDiagnostics: "fatal: Authentication failed for 'https://github.com/'"
        )
        guard case .authenticationFailure = error else {
            Issue.record("Expected authenticationFailure")
            return
        }
    }

    @Test func terminalPromptsDisabled() {
        let error = GitCloneErrorClassifier.classify(
            sanitizedDiagnostics: "fatal: could not read Username: terminal prompts disabled"
        )
        guard case .httpsCredentialUnavailable = error else {
            Issue.record("Expected httpsCredentialUnavailable")
            return
        }
    }

    @Test func sshPermissionDenied() {
        let error = GitCloneErrorClassifier.classify(
            sanitizedDiagnostics: "git@github.com: Permission denied (publickey)."
        )
        guard case .sshPermissionDenied = error else {
            Issue.record("Expected sshPermissionDenied")
            return
        }
    }

    @Test func hostKeyVerificationFailed() {
        let error = GitCloneErrorClassifier.classify(
            sanitizedDiagnostics: "Host key verification failed."
        )
        guard case .unknownSSHHost = error else {
            Issue.record("Expected unknownSSHHost")
            return
        }
    }

    @Test func dnsFailure() {
        let error = GitCloneErrorClassifier.classify(
            sanitizedDiagnostics: "fatal: unable to access 'https://bad.example/': Could not resolve host: bad.example"
        )
        guard case .dnsFailure = error else {
            Issue.record("Expected dnsFailure")
            return
        }
    }

    @Test func networkFailure() {
        let error = GitCloneErrorClassifier.classify(
            sanitizedDiagnostics: "fatal: unable to access 'https://example.com/': Failed to connect timed out"
        )
        guard case .networkFailure = error else {
            Issue.record("Expected networkFailure")
            return
        }
    }

    @Test func destinationExists() {
        let error = GitCloneErrorClassifier.classify(
            sanitizedDiagnostics: "fatal: destination path 'repo' already exists and is not an empty directory."
        )
        #expect(error == .destinationExists)
    }

    @Test func unknownErrorUsesSnippet() {
        let error = GitCloneErrorClassifier.classify(
            sanitizedDiagnostics: "fatal: something completely unexpected happened here"
        )
        guard case .nonzeroExit(_, let msg) = error else {
            Issue.record("Expected nonzeroExit")
            return
        }
        #expect(msg.contains("unexpected"))
    }

    @Test func redactionDoesNotExposeSecrets() {
        let redacted = GitCredentialRedactor.redactText(
            "fatal: https://user:secret@github.com/foo failed"
        )
        #expect(!redacted.contains("secret"))
        #expect(redacted.contains("REDACTED"))
    }
}
