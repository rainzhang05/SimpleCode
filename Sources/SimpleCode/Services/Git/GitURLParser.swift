import Foundation

enum GitURLParser {
    static func parse(_ input: String) -> Result<GitParsedURL, GitCloneError> {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyRepositoryURL) }
        if trimmed.contains("\n") || trimmed.contains("\0") {
            return .failure(.invalidRepositoryURL("Repository URL contains invalid characters."))
        }

        var hadCredentials = false
        var normalized = trimmed

        if let url = URL(string: trimmed) {
            if url.user != nil || url.password != nil {
                hadCredentials = true
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                components?.user = nil
                components?.password = nil
                if let stripped = components?.string {
                    normalized = stripped
                }
            }
        } else if trimmed.contains("@") && trimmed.contains("://") == false {
            // SCP-like: git@host:owner/repo.git
            if let atIndex = trimmed.firstIndex(of: "@"),
               let colonAfterHost = trimmed[atIndex...].dropFirst().firstIndex(of: ":") {
                let _ = colonAfterHost
            }
        }

        let folderName = deriveFolderName(from: trimmed)
        guard !folderName.isEmpty, folderName != ".", folderName != ".." else {
            return .failure(.invalidRepositoryURL("Could not derive a valid folder name from the URL."))
        }

        if let validationError = FilenameValidator.validate(folderName) {
            return .failure(.invalidDestinationName(validationError))
        }

        return .success(GitParsedURL(
            originalInput: trimmed,
            normalizedURL: normalized,
            derivedFolderName: folderName,
            hadEmbeddedCredentials: hadCredentials
        ))
    }

    static func deriveFolderName(from input: String) -> String {
        var trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        if let url = URL(string: trimmed), url.scheme != nil {
            var last = url.lastPathComponent
            if last.hasSuffix(".git") { last = String(last.dropLast(4)) }
            return last
        }

        // SCP-like git@host:owner/repo.git
        if let colonRange = trimmed.range(of: ":", options: .backwards) {
            var segment = String(trimmed[colonRange.upperBound...])
            while segment.hasSuffix("/") { segment.removeLast() }
            if segment.hasSuffix(".git") { segment = String(segment.dropLast(4)) }
            if let last = segment.split(separator: "/").last {
                return String(last)
            }
            return segment
        }

        var last = (trimmed as NSString).lastPathComponent
        if last.hasSuffix(".git") { last = String(last.dropLast(4)) }
        return last
    }
}
