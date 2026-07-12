import Foundation
import Testing
@testable import SimpleCode

struct HighlightingIntegrationTests {
    @Test func pagedScriptHighlightStartsInsideMultilineCommentWithCorrectState() async throws {
        let highlighter = ScriptPatternHighlighter(languageID: .javascript)
        let prefix = String(repeating: "const prefix = true;\n", count: 4_000)
        let commentBody = String(repeating: "comment body remains a comment\n", count: 4_000)
        let text = prefix + "/* open comment\n" + commentBody + "close */\nconst after = true;\n"
        let commentStart = (prefix as NSString).length
        let priorityLocation = commentStart + (commentBody as NSString).length / 2
        let priorityRange = NSRange(location: priorityLocation, length: 2_000)

        let page = await highlighter.prepareInitial(
            text: text,
            revision: 0,
            priorityUTF16Range: priorityRange
        )

        #expect(page.batch.coveredRanges == [priorityRange])
        let commentTokens = page.batch.tokens.filter { $0.category == .comment }
        #expect(commentTokens.contains { NSLocationInRange(priorityLocation, $0.range) })
        #expect(page.batch.tokens.allSatisfy {
            NSIntersectionRange($0.range, priorityRange).length > 0
        })
    }

    @Test func pagedScriptContinuationColorsACommentCloserSplitByThePageBoundary() async throws {
        let highlighter = ScriptPatternHighlighter(languageID: .javascript)
        let pageSize = InitialHighlightPaging.pageSizeUTF16
        let body = String(repeating: "x", count: pageSize - 3)
        let text = "/*" + body + "*/ const after = true;"
        let priorityRange = NSRange(location: 0, length: pageSize)

        let first = await highlighter.prepareInitial(
            text: text,
            revision: 0,
            priorityUTF16Range: priorityRange
        )
        let cursor = try #require(first.next)
        let second = try #require(await highlighter.continueInitial(cursor, pageSizeUTF16: pageSize))

        #expect(second.batch.coveredRanges.first?.location == pageSize)
        #expect(second.batch.tokens.contains { token in
            token.category == .comment && NSLocationInRange(pageSize, token.range)
        })
    }

    @Test func pagedScriptContinuationClosesATripleStringSplitByThePageBoundary() async throws {
        let highlighter = ScriptPatternHighlighter(languageID: .python)
        let pageSize = InitialHighlightPaging.pageSizeUTF16
        let body = String(repeating: "x", count: pageSize - 5)
        let text = "\"\"\"" + body + "\"\"\" def after():\n    return True\n"
        let priorityRange = NSRange(location: 0, length: pageSize)

        let first = await highlighter.prepareInitial(
            text: text,
            revision: 0,
            priorityUTF16Range: priorityRange
        )
        let cursor = try #require(first.next)
        let second = try #require(await highlighter.continueInitial(cursor, pageSizeUTF16: pageSize))
        let afterRange = (text as NSString).range(of: "def after")

        #expect(second.batch.tokens.contains { token in
            token.category == .string && NSLocationInRange(pageSize, token.range)
        })
        #expect(second.batch.tokens.contains { token in
            token.category == .keyword && NSIntersectionRange(token.range, afterRange).length > 0
        })
    }

    @Test func splitTripleCloserDoesNotPoisonAThirdPageCheckpoint() async throws {
        let highlighter = ScriptPatternHighlighter(languageID: .python)
        let pageSize = InitialHighlightPaging.pageSizeUTF16
        let body = String(repeating: "x", count: pageSize - 5)
        let trailingCode = String(repeating: " def after = True;", count: pageSize / 4)
        let text = "\"\"\"" + body + "\"\"\"" + trailingCode

        let first = await highlighter.prepareInitial(
            text: text,
            revision: 0,
            priorityUTF16Range: NSRange(location: 0, length: pageSize)
        )
        let firstCursor = try #require(first.next)
        let second = try #require(await highlighter.continueInitial(
            firstCursor,
            pageSizeUTF16: pageSize
        ))
        let secondCursor = try #require(second.next)
        let third = try #require(await highlighter.continueInitial(
            secondCursor,
            pageSizeUTF16: pageSize
        ))

        #expect(third.batch.coveredRanges.first?.location == pageSize * 2)
        #expect(third.batch.tokens.contains { $0.category == .keyword })
        #expect(!third.batch.tokens.contains { token in
            token.category == .string
                && NSIntersectionRange(token.range, third.batch.coveredRanges[0]).length > pageSize / 2
        })
    }

    @Test func pagedScriptViewportKeepsAnEscapedBacktickInsideTheTemplateString() async {
        let highlighter = ScriptPatternHighlighter(languageID: .javascript)
        let prefix = String(repeating: "const prefix = true;\n", count: 4_000)
        let templatePrefix = "const template = `start \\` still inside\n"
        let body = String(repeating: "template body remains a string\n", count: 4_000)
        let text = prefix + templatePrefix + body + "`;\nconst after = true;\n"
        let bodyStart = ((prefix + templatePrefix) as NSString).length
        let viewport = NSRange(location: bodyStart + (body as NSString).length / 2, length: 2_000)

        _ = await highlighter.prepareInitial(
            text: text,
            revision: 0,
            priorityUTF16Range: NSRange(location: 0, length: 2_000)
        )
        let result = await highlighter.scheduleViewport(
            fullText: text,
            revision: 0,
            visibleUTF16Range: viewport
        )

        #expect(result.priority.tokens.contains { token in
            token.category == .string && NSLocationInRange(viewport.location, token.range)
        })
    }

    @Test func pagedScriptViewportKeepsPythonTripleStringState() async {
        let highlighter = ScriptPatternHighlighter(languageID: .python)
        let prefix = String(repeating: "prefix = True\n", count: 4_000)
        let body = String(repeating: "triple body remains a string\n", count: 4_000)
        let text = prefix + "value = \"\"\"open\n" + body + "close\"\"\"\nafter = True\n"
        let bodyStart = ((prefix + "value = \"\"\"open\n") as NSString).length
        let viewport = NSRange(location: bodyStart + (body as NSString).length / 2, length: 2_000)

        _ = await highlighter.prepareInitial(
            text: text,
            revision: 0,
            priorityUTF16Range: NSRange(location: 0, length: 2_000)
        )
        let result = await highlighter.scheduleViewport(
            fullText: text,
            revision: 0,
            visibleUTF16Range: viewport
        )

        #expect(result.priority.tokens.contains { token in
            token.category == .string && NSLocationInRange(viewport.location, token.range)
        })
    }

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

    @Test func scriptPatternKeepsCommentMarkersInsideStringsAsStrings() async {
        let highlighter = ScriptPatternHighlighter(languageID: .typescript)
        let source = "const endpoint = \"https://example.test\" // live endpoint"

        let batch = await highlighter.load(text: source, revision: 1)

        #expect(batch.tokens.contains { token in
            token.category == .string
                && (source as NSString).substring(with: token.range).contains("https://")
        })
        #expect(batch.tokens.contains { token in
            token.category == .comment
                && (source as NSString).substring(with: token.range) == "// live endpoint"
        })
    }

    @Test func scriptPatternRehighlightsOnlyTheChangedLineWindow() async {
        let highlighter = ScriptPatternHighlighter(languageID: .typescript)
        let original = "const first = 1\nconst second = 2\nconst third = 3\nconst fourth = 4"
        _ = await highlighter.load(text: original, revision: 1)
        let changed = original.replacingOccurrences(of: "second", with: "renamed")
        let editStart = (original as NSString).range(of: "second")
        let result = await highlighter.applyEdit(
            fullText: changed,
            edit: TextEditDescriptor(
                startUTF16: editStart.location,
                oldEndUTF16: NSMaxRange(editStart),
                newEndUTF16: editStart.location + ("renamed" as NSString).length
            ),
            revision: 2,
            priorityUTF16Range: NSRange(location: 0, length: 0)
        )

        #expect(result.priority.coveredRanges.reduce(0) { $0 + $1.length } < changed.utf16.count)
        #expect(result.priority.tokens.contains { $0.category == .keyword })
    }

    @Test func scriptPatternKeepsSingleLineTemplateLiteralsIncremental() async {
        let highlighter = ScriptPatternHighlighter(languageID: .typescript)
        let original = "const label = `ready`\nconst first = 1\nconst second = 2\nconst third = 3"
        _ = await highlighter.load(text: original, revision: 1)
        let changed = original.replacingOccurrences(of: "second", with: "renamed")
        let editStart = (original as NSString).range(of: "second")

        let result = await highlighter.applyEdit(
            fullText: changed,
            edit: TextEditDescriptor(
                startUTF16: editStart.location,
                oldEndUTF16: NSMaxRange(editStart),
                newEndUTF16: editStart.location + ("renamed" as NSString).length
            ),
            revision: 2,
            priorityUTF16Range: NSRange(location: 0, length: 0)
        )

        #expect(result.priority.coveredRanges.reduce(0) { $0 + $1.length } < changed.utf16.count)
    }

    @Test func scriptPatternReparsesAfterCreatingAMultilineTemplateLiteral() async {
        let highlighter = ScriptPatternHighlighter(languageID: .typescript)
        let original = "const template = `prefix content suffix`\nconst first = 1\nconst second = 2\nconst third = 3"
        _ = await highlighter.load(text: original, revision: 1)

        let contentRange = (original as NSString).range(of: "content")
        let multiline = original.replacingOccurrences(of: "content", with: "content\ncontinued")
        _ = await highlighter.applyEdit(
            fullText: multiline,
            edit: TextEditDescriptor(
                startUTF16: contentRange.location,
                oldEndUTF16: NSMaxRange(contentRange),
                newEndUTF16: contentRange.location + ("content\ncontinued" as NSString).length
            ),
            revision: 2,
            priorityUTF16Range: NSRange(location: 0, length: 0)
        )

        let continuedRange = (multiline as NSString).range(of: "continued")
        let changed = multiline.replacingOccurrences(of: "continued", with: "changed")
        let result = await highlighter.applyEdit(
            fullText: changed,
            edit: TextEditDescriptor(
                startUTF16: continuedRange.location,
                oldEndUTF16: NSMaxRange(continuedRange),
                newEndUTF16: continuedRange.location + ("changed" as NSString).length
            ),
            revision: 3,
            priorityUTF16Range: NSRange(location: continuedRange.location, length: 7)
        )

        #expect(result.priority.tokens.contains { token in
            token.category == .string
                && (changed as NSString).substring(with: token.range).contains("changed")
        })
    }

    @Test func treeSitterKeepsDistantViewportAndEditRangesDisjoint() async throws {
        let highlighter = try #require(TreeSitterHighlighter(languageID: .swift))
        let source = "let first = 1\nlet second = 2\nlet third = 3\nlet fourth = 4\nlet fifth = 5"
        _ = await highlighter.load(text: source, revision: 1)
        let firstRange = (source as NSString).range(of: "first")
        let changed = source.replacingOccurrences(of: "first", with: "renamed")
        let distantRange = (changed as NSString).range(of: "fifth")

        let result = await highlighter.applyEdit(
            fullText: changed,
            edit: TextEditDescriptor(
                startUTF16: firstRange.location,
                oldEndUTF16: NSMaxRange(firstRange),
                newEndUTF16: firstRange.location + ("renamed" as NSString).length
            ),
            revision: 2,
            priorityUTF16Range: distantRange
        )

        #expect(result.priority.coveredRanges.count == 2)
        #expect(result.priority.coveredRanges.reduce(0) { $0 + $1.length } < changed.utf16.count)
    }

    @Test(arguments: [LanguageID.c, .cpp])
    func cFamilyTreeSitterQueriesClassifyFunctionsKeywordsAndStrings(language: LanguageID) async throws {
        let highlighter = try #require(TreeSitterHighlighter(languageID: language))
        let source = "int main() { return puts(\"hello\"); }"
        let batch = await highlighter.load(text: source, revision: 1)

        #expect(batch.tokens.contains { $0.category == .function })
        #expect(batch.tokens.contains { $0.category == .keyword })
        #expect(batch.tokens.contains { $0.category == .string })
    }

    @Test func jsonTreeSitterDoesNotPaintWholeContainersOverValues() async throws {
        let highlighter = try #require(TreeSitterHighlighter(languageID: .json))
        let source = "{\"name\": \"SimpleCode\", \"enabled\": true, \"count\": 2}"
        let batch = await highlighter.load(text: source, revision: 1)

        #expect(batch.tokens.contains { $0.category == .label })
        #expect(batch.tokens.contains { $0.category == .string })
        #expect(batch.tokens.contains { $0.category == .constant })
        #expect(batch.tokens.contains { $0.category == .number })
        #expect(!batch.tokens.contains { $0.range.length >= source.utf16.count })
    }

    @Test func highlightProviderFactorySelectsScriptPatternForPython() {
        let highlighter = HighlightProviderFactory.makeHighlighter(for: .python)
        #expect(highlighter is ScriptPatternHighlighter)
    }
}
