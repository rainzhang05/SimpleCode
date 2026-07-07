import Foundation

struct LanguageEditingProfile: Sendable, Equatable {
    /// Tokens or line suffixes that begin an indented block on the following line.
    let blockOpeners: [String]
    /// Keywords that reduce indentation when typed at the start of a line.
    let dedentKeywords: [String]
    /// When true, pressing Return inside an unclosed block opener increases indent on the new line.
    let indentAfterBlockOpener: Bool
    /// When true, dedent keywords align with the enclosing block's indentation level.
    let alignDedentKeywords: Bool

    init(
        blockOpeners: [String],
        dedentKeywords: [String],
        indentAfterBlockOpener: Bool = true,
        alignDedentKeywords: Bool = true
    ) {
        self.blockOpeners = blockOpeners
        self.dedentKeywords = dedentKeywords
        self.indentAfterBlockOpener = indentAfterBlockOpener
        self.alignDedentKeywords = alignDedentKeywords
    }
}

extension LanguageEditingProfile {
    static let plainText = LanguageEditingProfile(
        blockOpeners: [],
        dedentKeywords: [],
        indentAfterBlockOpener: false,
        alignDedentKeywords: false
    )

    static let swift = LanguageEditingProfile(
        blockOpeners: ["{", "case", "default"],
        dedentKeywords: ["}", "case", "default", "else", "catch"]
    )

    static let c = LanguageEditingProfile(
        blockOpeners: ["{", "case", "default"],
        dedentKeywords: ["}", "case", "default", "else"]
    )

    static let cpp = LanguageEditingProfile(
        blockOpeners: ["{", "case", "default"],
        dedentKeywords: ["}", "case", "default", "else", "catch"]
    )

    static let python = LanguageEditingProfile(
        blockOpeners: [
            ":", "def", "class", "if", "elif", "else", "for", "while",
            "try", "except", "finally", "with", "match", "case"
        ],
        dedentKeywords: ["elif", "else", "except", "finally", "case"]
    )

    static let javascript = LanguageEditingProfile(
        blockOpeners: ["{", "case", "default"],
        dedentKeywords: ["}", "case", "default", "else", "catch", "finally"]
    )

    static let typescript = LanguageEditingProfile(
        blockOpeners: ["{", "case", "default"],
        dedentKeywords: ["}", "case", "default", "else", "catch", "finally"]
    )

    static let tsx = LanguageEditingProfile(
        blockOpeners: ["{", "case", "default"],
        dedentKeywords: ["}", "case", "default", "else", "catch", "finally"]
    )

    static let json = LanguageEditingProfile(
        blockOpeners: ["{", "["],
        dedentKeywords: ["}", "]"],
        indentAfterBlockOpener: true,
        alignDedentKeywords: false
    )

    static let markdown = LanguageEditingProfile(
        blockOpeners: [],
        dedentKeywords: [],
        indentAfterBlockOpener: false,
        alignDedentKeywords: false
    )

    static let shell = LanguageEditingProfile(
        blockOpeners: ["then", "do", "{"],
        dedentKeywords: ["elif", "else", "fi", "done", "esac", "}"]
    )

    static let assembly = LanguageEditingProfile(
        blockOpeners: [],
        dedentKeywords: [],
        indentAfterBlockOpener: false,
        alignDedentKeywords: false
    )

    static func profile(for id: LanguageID) -> LanguageEditingProfile {
        switch id {
        case .plainText: return .plainText
        case .swift: return .swift
        case .c: return .c
        case .cpp: return .cpp
        case .python: return .python
        case .javascript: return .javascript
        case .typescript: return .typescript
        case .tsx: return .tsx
        case .json: return .json
        case .markdown: return .markdown
        case .shell: return .shell
        case .assembly: return .assembly
        }
    }
}
