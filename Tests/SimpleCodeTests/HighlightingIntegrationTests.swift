import Foundation
import Testing
@testable import SimpleCode

struct HighlightingIntegrationTests {
    @Test func swiftTreeSitterProducesTokens() async throws {
        guard let highlighter = TreeSitterHighlighter(languageID: .swift) else {
            Issue.record("Swift tree-sitter highlighter failed to initialize")
            return
        }
        let source = """
        import Foundation

        struct Greeter {
            let name: String
            func greet() -> String { "Hello, \\(name)" }
        }
        """
        let batch = await highlighter.load(text: source, revision: 1)
        #expect(!batch.tokens.isEmpty)
        #expect(batch.tokens.contains { $0.category == .keyword })
        #expect(batch.tokens.contains { $0.category == .type || $0.category == .variable })
    }

    @Test func assemblyPatternProducesTokens() async {
        guard let highlighter = HighlightProviderFactory.makeHighlighter(for: .assembly) as? AssemblyPatternHighlighter else {
            Issue.record("Assembly highlighter failed to initialize")
            return
        }
        let source = """
        .section __TEXT
        _main:
            movq %rdi, %rax
            ret
        """
        let batch = await highlighter.load(text: source, revision: 1)
        #expect(!batch.tokens.isEmpty)
        #expect(batch.tokens.contains { $0.category == .preprocessor || $0.category == .label })
        #expect(batch.tokens.contains { $0.category == .keyword })
    }

    @Test func highlightProviderFactorySelectsTreeSitterForSwift() {
        let highlighter = HighlightProviderFactory.makeHighlighter(for: .swift)
        #expect(highlighter is TreeSitterHighlighter)
    }

    @Test func highlightProviderFactorySelectsAssemblyPattern() {
        let highlighter = HighlightProviderFactory.makeHighlighter(for: .assembly)
        #expect(highlighter is AssemblyPatternHighlighter)
    }

    @Test func pythonScriptPatternProducesTokens() async {
        guard let highlighter = HighlightProviderFactory.makeHighlighter(for: .python) as? ScriptPatternHighlighter else {
            Issue.record("Python script-pattern highlighter failed to initialize")
            return
        }
        let source = "def greet(name):\n    return f'Hello, {name}'\n"
        let batch = await highlighter.load(text: source, revision: 1)
        #expect(!batch.tokens.isEmpty)
        #expect(batch.tokens.contains { $0.category == .keyword })
    }

    @Test func highlightProviderFactorySelectsScriptPatternForPython() {
        let highlighter = HighlightProviderFactory.makeHighlighter(for: .python)
        #expect(highlighter is ScriptPatternHighlighter)
    }
}
