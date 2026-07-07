import Foundation

/// Classifies sanitized git stderr into user-facing clone errors.
///
/// Environment note: clones set `GIT_TERMINAL_PROMPT=0` to disable interactive
/// terminal username/password prompts. Ordinary credential-helper and macOS Keychain
/// behavior is preserved. Failures that require prior Terminal authentication are
/// reported as authentication failures when stderr indicates prompt unavailability.
enum GitCloneErrorClassifier {
    static func classify(sanitizedDiagnostics: String, exitCode: Int32 = 1) -> GitCloneError {
        let lower = sanitizedDiagnostics.lowercased()

        if lower.contains("authentication failed")
            || lower.contains("could not read username")
            || lower.contains("invalid username or password")
            || lower.contains("terminal prompts disabled")
            || lower.contains("could not read password") {
            if lower.contains("terminal prompts disabled") {
                return .httpsCredentialUnavailable(
                    "HTTPS credentials are unavailable without an interactive prompt. " +
                    "Configure a credential helper or authenticate in Terminal first."
                )
            }
            return .authenticationFailure(
                "Authentication failed. Configure credentials through Git, Keychain, or SSH before cloning."
            )
        }

        if lower.contains("permission denied (publickey)")
            || lower.contains("publickey denied") {
            return .sshPermissionDenied(
                "SSH authentication failed. Ensure your SSH key is loaded and authorized for this host."
            )
        }

        if lower.contains("host key verification failed") {
            return .unknownSSHHost(
                "SSH host key verification failed. Authenticate once in Terminal, then retry."
            )
        }

        if lower.contains("could not resolve host") || lower.contains("name or service not known") {
            return .dnsFailure("Could not resolve the repository host. Check the URL and DNS.")
        }

        if lower.contains("timed out")
            || lower.contains("unable to access")
            || lower.contains("connection refused")
            || lower.contains("network is unreachable") {
            return .networkFailure("Network error while cloning. Check the URL and connection.")
        }

        if lower.contains("already exists and is not an empty directory") {
            return .destinationExists
        }

        if lower.contains("could not create")
            || (lower.contains("permission denied") && lower.contains("unable to create")) {
            return .destinationNotWritable
        }

        let snippet = String(sanitizedDiagnostics.suffix(500))
        return .nonzeroExit(exitCode, snippet)
    }
}
