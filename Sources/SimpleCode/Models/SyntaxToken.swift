import Foundation

/// Coarse, theme-facing syntax categories. Tree-sitter capture names (e.g.
/// `keyword.function`, `variable.parameter`, `comment.documentation`) are mapped down
/// to this small, stable set so the highlighter and the color theme never need to
/// know about grammar-specific capture naming (see `HighlightTheme.category(forCapture:)`).
enum SyntaxCategory: Sendable, CaseIterable, Hashable {
    case keyword
    case controlFlow
    case type
    case function
    case variable
    case string
    case number
    case comment
    case documentationComment
    case `operator`
    case punctuation
    case preprocessor
    case attribute
    case constant
    case label
    case invalid
    case plain
    /// Legacy alias mapped to `.operator` in theme resolution.
    case operatorOrPunctuation
}

/// A single highlighted range, produced by the syntax pipeline and applied verbatim
/// to the text storage. `range` is always a UTF-16-based `NSRange`, matching what
/// `NSTextStorage` expects — never a byte offset.
struct SyntaxToken: Equatable, Sendable {
    let range: NSRange
    let category: SyntaxCategory
}
