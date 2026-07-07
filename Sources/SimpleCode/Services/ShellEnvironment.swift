import Foundation

/// Resolves the user's configured login shell and builds the environment a PTY
/// session should inherit.
enum ShellEnvironment {
    /// The user's login shell path (e.g. `/bin/zsh`), read from the directory
    /// services record for the current user — the same source `Terminal.app` uses —
    /// rather than trusting the `SHELL` environment variable alone, which may be
    /// absent in some launch contexts (e.g. launched from Finder/Dock).
    static func loginShellPath() -> String {
        if let pwShell = currentUserShellFromDirectoryServices() {
            return pwShell
        }
        if let envShell = ProcessInfo.processInfo.environment["SHELL"], !envShell.isEmpty {
            return envShell
        }
        return "/bin/zsh"
    }

    /// Builds the environment dictionary for a new PTY session: the process's own
    /// environment, plus a few variables a real interactive terminal always sets.
    static func makeEnvironment(workingDirectory: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["LANG"] = environment["LANG"] ?? "en_US.UTF-8"
        environment["PWD"] = workingDirectory.path
        return environment
    }

    private static func currentUserShellFromDirectoryServices() -> String? {
        guard let passwd = getpwuid(getuid()) else { return nil }
        let shellPointer = passwd.pointee.pw_shell
        guard let shellPointer else { return nil }
        let path = String(cString: shellPointer)
        return path.isEmpty ? nil : path
    }
}
