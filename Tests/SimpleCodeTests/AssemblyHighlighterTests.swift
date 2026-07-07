import Foundation
import Testing
@testable import SimpleCode

struct AssemblyHighlighterTests {
    @Test func highlightsIntelInstructionAndRegister() async {
        let highlighter = AssemblyPatternHighlighter()
        let source = "mov rax, rbx\n; comment"
        let batch = await highlighter.load(text: source, revision: 1)
        #expect(!batch.tokens.isEmpty)
        #expect(batch.tokens.contains { $0.category == .keyword })
        #expect(batch.tokens.contains { $0.category == .variable })
        #expect(batch.tokens.contains { $0.category == .comment })
    }

    @Test func highlightsATTSyntax() async {
        let highlighter = AssemblyPatternHighlighter()
        let source = "movq %rax, %rbx"
        let batch = await highlighter.load(text: source, revision: 1)
        #expect(batch.tokens.contains { $0.category == .keyword })
        #expect(batch.tokens.contains { $0.category == .variable })
    }

    @Test func highlightsAArch64Syntax() async {
        let highlighter = AssemblyPatternHighlighter()
        let source = "mov x0, x1"
        let batch = await highlighter.load(text: source, revision: 1)
        #expect(batch.tokens.contains { $0.category == .keyword })
        #expect(batch.tokens.contains { $0.category == .variable })
    }

    @Test func highlightsHexImmediate() async {
        let highlighter = AssemblyPatternHighlighter()
        let source = "mov rax, 0x10"
        let batch = await highlighter.load(text: source, revision: 1)
        #expect(batch.tokens.contains { $0.category == .number })
    }
}
