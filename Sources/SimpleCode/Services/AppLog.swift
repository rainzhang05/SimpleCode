import OSLog

/// Central place to obtain `Logger` instances for developer diagnostics.
///
/// Convention enforced at every call site: never log file contents, shell command
/// arguments that might contain credentials/tokens, environment variable values,
/// or bookmark bytes. Log intent and outcome ("failed to resolve bookmark: <error>"),
/// not payloads.
enum AppLog {
    private static let subsystem = "com.simplecode.app"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let filesystem = Logger(subsystem: subsystem, category: "filesystem")
    static let editor = Logger(subsystem: subsystem, category: "editor")
    static let syntax = Logger(subsystem: subsystem, category: "syntax")
    static let terminal = Logger(subsystem: subsystem, category: "terminal")
    static let run = Logger(subsystem: subsystem, category: "run")
    static let git = Logger(subsystem: subsystem, category: "git")
}
