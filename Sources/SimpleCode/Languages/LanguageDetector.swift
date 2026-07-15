import Foundation

struct LanguageWorkspaceContext: Sendable, Equatable {
    /// Lowercased file extensions present in the same directory as the file being detected.
    let siblingExtensions: Set<String>

    init(siblingExtensions: Set<String> = []) {
        self.siblingExtensions = Set(siblingExtensions.map { $0.lowercased() })
    }

    static let empty = LanguageWorkspaceContext()
}

enum LanguageDetector {
    private static let cppHeaderSignals: Set<String> = ["cpp", "cc", "cxx", "hpp", "hh", "hxx"]

    static func detect(
        url: URL,
        content: String = "",
        workspaceContext: LanguageWorkspaceContext = .empty,
        override: LanguageID? = nil
    ) -> LanguageID {
        if let override {
            return override
        }

        if let exactMatch = LanguageRegistry.languageID(forExactFilename: url.lastPathComponent) {
            return exactMatch
        }

        let normalizedExtension = url.pathExtension.lowercased()

        if let extensionMatch = LanguageRegistry.languageID(forExtension: normalizedExtension) {
            return extensionMatch
        }

        if let shebangMatch = detectShebang(in: content) {
            return shebangMatch
        }

        if let heuristicMatch = conservativeHeuristic(
            url: url,
            normalizedExtension: normalizedExtension,
            workspaceContext: workspaceContext
        ) {
            return heuristicMatch
        }

        return .plainText
    }

    private static func detectShebang(in content: String) -> LanguageID? {
        guard let firstLine = content.firstLineSubstring else { return nil }
        let trimmed = firstLine.drop(while: { $0.isWhitespace })
        guard trimmed.hasPrefix("#!") else { return nil }

        let interpreter = trimmed.dropFirst(2).lowercased()
        for definition in LanguageRegistry.all {
            guard !definition.shebangPatterns.isEmpty else { continue }
            if definition.shebangPatterns.contains(where: { interpreter.contains($0.lowercased()) }) {
                return definition.id
            }
        }
        return nil
    }

    private static func conservativeHeuristic(
        url: URL,
        normalizedExtension: String,
        workspaceContext: LanguageWorkspaceContext
    ) -> LanguageID? {
        _ = url
        if normalizedExtension == "h" {
            if !workspaceContext.siblingExtensions.isDisjoint(with: cppHeaderSignals) {
                return .cpp
            }
            return .c
        }
        return nil
    }
}

private extension String {
    var firstLineSubstring: Substring? {
        guard let newlineIndex = firstIndex(where: { $0.isNewline }) else {
            return isEmpty ? nil : self[...]
        }
        return self[..<newlineIndex]
    }
}
