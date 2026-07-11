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

    @Test func keepsStringDelimitersAndArmImmediatesOutOfCommentDetection() async {
        let highlighter = AssemblyPatternHighlighter()
        let source = "mov x0, #42 // \"; literal\""
        let batch = await highlighter.load(text: source, revision: 1)

        #expect(batch.tokens.contains { $0.category == .keyword })
        #expect(batch.tokens.contains { $0.category == .number })
        #expect(batch.tokens.contains { $0.category == .comment })
    }

    @Test func incrementallyRehighlightsTheEditedAssemblyLineWindow() async {
        let highlighter = AssemblyPatternHighlighter()
        let original = "mov rax, rbx\nadd rax, 1\nret\nnop"
        _ = await highlighter.load(text: original, revision: 1)
        let oldRange = (original as NSString).range(of: "add")
        let changed = original.replacingOccurrences(of: "add", with: "sub")

        let result = await highlighter.applyEdit(
            fullText: changed,
            edit: TextEditDescriptor(
                startUTF16: oldRange.location,
                oldEndUTF16: NSMaxRange(oldRange),
                newEndUTF16: NSMaxRange(oldRange)
            ),
            revision: 2,
            priorityUTF16Range: NSRange(location: 0, length: 0)
        )

        #expect(result.priority.coveredRanges.reduce(0) { $0 + $1.length } < changed.utf16.count)
        #expect(result.priority.tokens.contains { $0.category == .keyword })
    }
}
