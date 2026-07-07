import Foundation

enum LanguageID: String, CaseIterable, Codable, Equatable, Sendable {
    case plainText
    case swift
    case c
    case cpp
    case python
    case javascript
    case typescript
    case tsx
    case json
    case markdown
    case shell
    case assembly

    var displayName: String {
        switch self {
        case .plainText: return "Plain Text"
        case .swift: return "Swift"
        case .c: return "C"
        case .cpp: return "C++"
        case .python: return "Python"
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .tsx: return "TSX"
        case .json: return "JSON"
        case .markdown: return "Markdown"
        case .shell: return "Shell"
        case .assembly: return "Assembly"
        }
    }
}
