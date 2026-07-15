import AppKit

/// Maps tree-sitter capture names to semantic categories and resolves colors from settings.
enum HighlightTheme {
    static func category(forCapture name: String) -> SyntaxCategory? {
        if let exact = exactMatches[name] {
            return exact
        }
        if let dot = name.firstIndex(of: ".") {
            return prefixMatches[String(name[..<dot])]
        }
        return prefixMatches[name]
    }

    private static let exactMatches: [String: SyntaxCategory] = [
        "constructor": .function,
        "comment.documentation": .documentationComment,
        "constant.builtin": .constant,
        "constant.macro": .constant,
        "boolean": .constant,
        "number.float": .number,
        "string.escape": .string,
        "string.regexp": .string,
        "character.special": .plain,
        "keyword.return": .controlFlow,
        "keyword.break": .controlFlow,
        "keyword.continue": .controlFlow,
        "keyword.conditional": .controlFlow,
        "keyword.repeat": .controlFlow,
        "preproc": .preprocessor,
        "include": .preprocessor,
        "define": .preprocessor
    ]

    private static let prefixMatches: [String: SyntaxCategory] = [
        "keyword": .keyword,
        "type": .type,
        "function": .function,
        "variable": .variable,
        "string": .string,
        "number": .number,
        "comment": .comment,
        "operator": .operator,
        "punctuation": .punctuation,
        "attribute": .attribute,
        "constant": .constant,
        "label": .label,
        "preproc": .preprocessor,
        "directive": .preprocessor,
        "error": .invalid
    ]

    static func color(for category: SyntaxCategory, appearance: EditorAppearance) -> NSColor {
        let isDark = appearance == .dark
        return SyntaxPaletteDefaults.pair(for: category).resolved(isDark: isDark)
    }
}

enum EditorAppearance {
    case light
    case dark
}
