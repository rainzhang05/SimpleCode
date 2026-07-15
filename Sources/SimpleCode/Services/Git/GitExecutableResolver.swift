import Foundation

enum GitExecutableResolver: Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var cachedPath: String?

    static func resolve() -> Result<String, GitCloneError> {
        lock.lock()
        defer { lock.unlock() }
        if let cachedPath { return .success(cachedPath) }

        let candidates = ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                cachedPath = path
                return .success(path)
            }
        }

        if let xcrunPath = runXcrunFindGit(), FileManager.default.isExecutableFile(atPath: xcrunPath) {
            cachedPath = xcrunPath
            return .success(xcrunPath)
        }

        return .failure(.gitUnavailable)
    }

    private static func runXcrunFindGit() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--find", "git"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return path?.isEmpty == false ? path : nil
        } catch {
            return nil
        }
    }
}
