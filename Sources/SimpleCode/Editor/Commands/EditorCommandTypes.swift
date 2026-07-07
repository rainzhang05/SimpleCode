import Foundation

struct TextEdit: Equatable, Sendable {
    let range: NSRange
    let replacement: String
}

struct EditorCommandResult: Equatable, Sendable {
    let edits: [TextEdit]
    let resultingSelections: [NSRange]
}

/// Token ranges (UTF-16) used to skip strings and comments during bracket/pair logic.
struct SyntaxContext: Equatable, Sendable {
    let stringRanges: [NSRange]
    let commentRanges: [NSRange]

    static let empty = SyntaxContext(stringRanges: [], commentRanges: [])

    func isInsideSpecialToken(at location: Int) -> Bool {
        stringRanges.contains { NSLocationInRange(location, $0) }
            || commentRanges.contains { NSLocationInRange(location, $0) }
    }
}

enum EditorCommandLanguage: String, Equatable, Sendable {
    case swift
    case cStyle
    case python
    case shell
    case makefile
    case plainText

    var lineCommentPrefix: String? {
        switch self {
        case .swift, .cStyle: return "//"
        case .python, .shell, .makefile: return "#"
        case .plainText: return nil
        }
    }

    var usesTabsForIndent: Bool {
        self == .makefile
    }
}

struct IndentationOptions: Equatable, Sendable {
    var language: EditorCommandLanguage
    var usesTabs: Bool
    var tabWidth: Int

    init(
        language: EditorCommandLanguage,
        usesTabs: Bool? = nil,
        tabWidth: Int = 4
    ) {
        self.language = language
        self.usesTabs = usesTabs ?? language.usesTabsForIndent
        self.tabWidth = max(1, tabWidth)
    }

    var indentUnit: String {
        usesTabs ? "\t" : String(repeating: " ", count: tabWidth)
    }
}
