import Foundation

enum LanguageRegistry {
    private static let bracePairs: [BracketPair] = [
        BracketPair(open: "(", close: ")"),
        BracketPair(open: "[", close: "]"),
        BracketPair(open: "{", close: "}"),
        BracketPair(open: "\"", close: "\""),
        BracketPair(open: "'", close: "'"),
    ]

    private static let cStyleBlockComment = BlockCommentDelimiters(open: "/*", close: "*/")

    static let makefileExactFilenames: Set<String> = ["makefile", "gnumakefile"]

    static let all: [LanguageDefinition] = [
        LanguageDefinition(
            id: .plainText,
            fileExtensions: [],
            indentProfile: .minimal,
            defaultTabWidth: nil,
            highlightingAvailable: false,
            highlighterKind: .none
        ),
        LanguageDefinition(
            id: .swift,
            fileExtensions: ["swift"],
            lineCommentToken: "//",
            blockComment: cStyleBlockComment,
            pairs: bracePairs,
            indentProfile: .brace,
            highlightingAvailable: true,
            highlighterKind: .treeSitter,
            treeSitterResourceName: "Swift"
        ),
        LanguageDefinition(
            id: .c,
            fileExtensions: ["c"],
            lineCommentToken: "//",
            blockComment: cStyleBlockComment,
            pairs: bracePairs,
            indentProfile: .brace,
            highlightingAvailable: true,
            highlighterKind: .treeSitter,
            treeSitterResourceName: "C"
        ),
        LanguageDefinition(
            id: .cpp,
            fileExtensions: ["cpp", "cc", "cxx", "hpp", "hh", "hxx"],
            lineCommentToken: "//",
            blockComment: cStyleBlockComment,
            pairs: bracePairs,
            indentProfile: .brace,
            highlightingAvailable: true,
            highlighterKind: .treeSitter,
            treeSitterResourceName: "Cpp"
        ),
        LanguageDefinition(
            id: .python,
            fileExtensions: ["py", "pyw", "pyi"],
            shebangPatterns: ["python", "python2", "python3"],
            lineCommentToken: "#",
            pairs: [
                BracketPair(open: "(", close: ")"),
                BracketPair(open: "[", close: "]"),
                BracketPair(open: "{", close: "}"),
                BracketPair(open: "\"", close: "\""),
                BracketPair(open: "'", close: "'"),
            ],
            indentProfile: .colon,
            highlightingAvailable: true,
            highlighterKind: .scriptPattern
        ),
        LanguageDefinition(
            id: .javascript,
            fileExtensions: ["js", "mjs", "cjs", "jsx"],
            shebangPatterns: ["node"],
            lineCommentToken: "//",
            blockComment: cStyleBlockComment,
            pairs: bracePairs,
            indentProfile: .brace,
            highlightingAvailable: true,
            highlighterKind: .scriptPattern
        ),
        LanguageDefinition(
            id: .typescript,
            fileExtensions: ["ts", "mts", "cts"],
            lineCommentToken: "//",
            blockComment: cStyleBlockComment,
            pairs: bracePairs,
            indentProfile: .brace,
            highlightingAvailable: true,
            highlighterKind: .scriptPattern
        ),
        LanguageDefinition(
            id: .tsx,
            fileExtensions: ["tsx"],
            lineCommentToken: "//",
            blockComment: cStyleBlockComment,
            pairs: bracePairs,
            indentProfile: .brace,
            highlightingAvailable: true,
            highlighterKind: .scriptPattern
        ),
        LanguageDefinition(
            id: .json,
            fileExtensions: ["json", "jsonc"],
            pairs: [
                BracketPair(open: "{", close: "}"),
                BracketPair(open: "[", close: "]"),
                BracketPair(open: "\"", close: "\""),
            ],
            indentProfile: .minimal,
            defaultTabWidth: 2,
            highlightingAvailable: true,
            highlighterKind: .treeSitter,
            treeSitterResourceName: "JSON"
        ),
        LanguageDefinition(
            id: .markdown,
            fileExtensions: ["md", "markdown", "mdown", "mkd"],
            indentProfile: .minimal,
            highlightingAvailable: true,
            highlighterKind: .treeSitter,
            treeSitterResourceName: "Markdown"
        ),
        LanguageDefinition(
            id: .shell,
            fileExtensions: ["sh", "bash", "zsh", "ksh"],
            exactFilenames: [
                "Makefile",
                "GNUmakefile",
                ".bashrc",
                ".zshrc",
                ".profile",
                ".bash_profile",
            ],
            shebangPatterns: ["bash", "sh", "zsh", "dash", "ksh"],
            lineCommentToken: "#",
            pairs: [
                BracketPair(open: "(", close: ")"),
                BracketPair(open: "{", close: "}"),
                BracketPair(open: "\"", close: "\""),
                BracketPair(open: "'", close: "'"),
            ],
            indentProfile: .shell,
            highlightingAvailable: true,
            highlighterKind: .treeSitter,
            treeSitterResourceName: "Shell"
        ),
        LanguageDefinition(
            id: .assembly,
            fileExtensions: ["s", "asm", "S"],
            lineCommentToken: ";",
            indentProfile: .assembly,
            highlightingAvailable: true,
            highlighterKind: .assemblyPattern
        ),
    ]

    static let byID: [LanguageID: LanguageDefinition] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }()

    private static let extensionMap: [String: LanguageID] = {
        var map: [String: LanguageID] = [:]
        for definition in all {
            for ext in definition.fileExtensions {
                map[ext.lowercased()] = definition.id
            }
        }
        return map
    }()

    private static let exactFilenameMap: [String: LanguageID] = {
        var map: [String: LanguageID] = [:]
        for definition in all {
            for name in definition.exactFilenames {
                map[name.lowercased()] = definition.id
            }
        }
        return map
    }()

    static func definition(for id: LanguageID) -> LanguageDefinition {
        guard let definition = byID[id] else {
            preconditionFailure("Missing language definition for \(id.rawValue)")
        }
        return definition
    }

    /// Returns the language definition, applying per-file overrides such as Makefile tab insertion.
    static func definition(for id: LanguageID, url: URL) -> LanguageDefinition {
        var definition = self.definition(for: id)
        if isMakefile(url) {
            definition = LanguageDefinition(
                id: definition.id,
                displayName: definition.displayName,
                fileExtensions: definition.fileExtensions,
                exactFilenames: definition.exactFilenames,
                shebangPatterns: definition.shebangPatterns,
                lineCommentToken: definition.lineCommentToken,
                blockComment: definition.blockComment,
                pairs: definition.pairs,
                indentProfile: definition.indentProfile,
                defaultTabWidth: definition.defaultTabWidth,
                insertSpacesOverride: false,
                highlightingAvailable: definition.highlightingAvailable,
                highlighterKind: definition.highlighterKind,
                treeSitterResourceName: definition.treeSitterResourceName
            )
        }
        return definition
    }

    static func languageID(forExtension extension: String) -> LanguageID? {
        extensionMap[`extension`.lowercased()]
    }

    static func languageID(forExactFilename filename: String) -> LanguageID? {
        exactFilenameMap[filename.lowercased()]
    }

    static func isMakefile(_ url: URL) -> Bool {
        makefileExactFilenames.contains(url.lastPathComponent.lowercased())
    }
}
