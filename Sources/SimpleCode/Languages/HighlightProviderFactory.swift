import Foundation

enum HighlightProviderFactory {
    static func makeHighlighter(for languageID: LanguageID) -> (any SyntaxHighlighter)? {
        let definition = LanguageRegistry.definition(for: languageID)
        guard definition.highlightingAvailable else { return nil }

        switch definition.highlighterKind {
        case .treeSitter:
            return TreeSitterHighlighter(languageID: languageID)
        case .assemblyPattern:
            return AssemblyPatternHighlighter()
        case .scriptPattern:
            return ScriptPatternHighlighter(languageID: languageID)
        case .none:
            return nil
        }
    }
}
