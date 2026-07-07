import Foundation

struct BlockCommentDelimiters: Sendable, Equatable {
    let open: String
    let close: String
}

struct BracketPair: Sendable, Equatable {
    let open: String
    let close: String
}

enum IndentProfile: String, Sendable, Equatable {
    case brace
    case colon
    case shell
    case assembly
    case minimal
}

enum HighlighterKind: String, Sendable, Equatable {
    case treeSitter
    case assemblyPattern
    case scriptPattern
    case none
}

struct LanguageDefinition: Sendable, Equatable {
    let id: LanguageID
    let displayName: String
    let fileExtensions: [String]
    let exactFilenames: [String]
    let shebangPatterns: [String]
    let lineCommentToken: String?
    let blockComment: BlockCommentDelimiters?
    let pairs: [BracketPair]
    let indentProfile: IndentProfile
    let defaultTabWidth: Int?
    let insertSpacesOverride: Bool?
    let highlightingAvailable: Bool
    let highlighterKind: HighlighterKind
    let treeSitterResourceName: String?

    init(
        id: LanguageID,
        displayName: String? = nil,
        fileExtensions: [String] = [],
        exactFilenames: [String] = [],
        shebangPatterns: [String] = [],
        lineCommentToken: String? = nil,
        blockComment: BlockCommentDelimiters? = nil,
        pairs: [BracketPair] = [],
        indentProfile: IndentProfile,
        defaultTabWidth: Int? = 4,
        insertSpacesOverride: Bool? = nil,
        highlightingAvailable: Bool = false,
        highlighterKind: HighlighterKind = .none,
        treeSitterResourceName: String? = nil
    ) {
        self.id = id
        self.displayName = displayName ?? id.displayName
        self.fileExtensions = fileExtensions
        self.exactFilenames = exactFilenames
        self.shebangPatterns = shebangPatterns
        self.lineCommentToken = lineCommentToken
        self.blockComment = blockComment
        self.pairs = pairs
        self.indentProfile = indentProfile
        self.defaultTabWidth = defaultTabWidth
        self.insertSpacesOverride = insertSpacesOverride
        self.highlightingAvailable = highlightingAvailable
        self.highlighterKind = highlighterKind
        self.treeSitterResourceName = treeSitterResourceName
    }
}
