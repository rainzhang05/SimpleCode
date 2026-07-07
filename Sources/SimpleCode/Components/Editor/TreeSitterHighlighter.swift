import Foundation
import SwiftTreeSitter
import TreeSitterC
import TreeSitterCPP
import TreeSitterJSON
import TreeSitterMarkdown
import TreeSitterSwift
import TreeSitterBash

/// Owns the tree-sitter parser, mutable tree, and compiled query for exactly one open
/// document, and produces syntax tokens off the main actor.
actor TreeSitterHighlighter: SyntaxHighlighter {
    private let parser: Parser
    private let query: Query
    private var tree: MutableTree?
    private var pendingRetryUTF16Ranges: [NSRange] = []

    init?(languageID: LanguageID) {
        guard let configuration = Self.configuration(for: languageID) else {
            AppLog.syntax.error("No tree-sitter configuration for \(languageID.rawValue, privacy: .public)")
            return nil
        }

        let languagePointer = configuration.languagePointer
        guard let pointer = languagePointer() else {
            AppLog.syntax.error("Tree-sitter language pointer was nil for \(languageID.rawValue, privacy: .public)")
            return nil
        }
        let language = Language(pointer)
        let parser = Parser()

        do {
            try parser.setLanguage(language)
        } catch {
            AppLog.syntax.error(
                "Failed to set the \(languageID.rawValue, privacy: .public) tree-sitter language: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }

        guard let queriesURL = Self.highlightsQueryURL(resourceName: configuration.resourceName) else {
            AppLog.syntax.error(
                "Bundled highlights.scm resource was not found for \(languageID.rawValue, privacy: .public)."
            )
            return nil
        }

        do {
            self.query = try Query(language: language, url: queriesURL)
        } catch {
            AppLog.syntax.error(
                "Failed to compile the \(languageID.rawValue, privacy: .public) highlight query: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }

        self.parser = parser
        self.tree = nil
    }

    func load(text: String, revision: Int) async -> HighlightBatch {
        let newTree = parser.parse(text)
        tree = newTree
        pendingRetryUTF16Ranges = []
        let tokens = newTree.map { highlightTokens(in: $0, restrictedTo: nil) } ?? []
        let wholeDocument = NSRange(location: 0, length: text.utf16.count)
        return HighlightBatch(revision: revision, coveredRanges: [wholeDocument], tokens: tokens)
    }

    func applyEdit(
        fullText: String,
        edit: TextEditDescriptor,
        revision: Int,
        priorityUTF16Range: NSRange
    ) async -> (priority: HighlightBatch, remainder: HighlightBatch?) {
        let editPointRange = NSRange(location: edit.startUTF16, length: max(0, edit.newEndUTF16 - edit.startUTF16))
        let priorityRange = EditorVisibleRange.union(priorityUTF16Range, editPointRange, documentLength: fullText.utf16.count)

        let parseResult = incrementalParse(fullText: fullText, edit: edit, failedRevision: revision)
        guard let parseResult else {
            return (
                HighlightBatch(revision: revision, coveredRanges: [priorityRange], tokens: []),
                nil
            )
        }

        return batches(
            tree: parseResult.tree,
            changedUTF16Ranges: parseResult.changedUTF16Ranges,
            revision: revision,
            priorityUTF16Range: priorityRange,
            includePendingRetry: true
        )
    }

    func scheduleViewport(
        fullText: String,
        revision: Int,
        visibleUTF16Range: NSRange
    ) async -> (priority: HighlightBatch, remainder: HighlightBatch?) {
        guard let tree else {
            return (
                HighlightBatch(revision: revision, coveredRanges: [visibleUTF16Range], tokens: []),
                nil
            )
        }

        return batches(
            tree: tree,
            changedUTF16Ranges: [],
            revision: revision,
            priorityUTF16Range: visibleUTF16Range,
            includePendingRetry: true
        )
    }

    private struct ParseResult {
        let tree: MutableTree
        let changedUTF16Ranges: [NSRange]
    }

    private struct LanguageConfiguration {
        let resourceName: String
        let languagePointer: @Sendable () -> OpaquePointer?
    }

    private static func configuration(for languageID: LanguageID) -> LanguageConfiguration? {
        let definition = LanguageRegistry.definition(for: languageID)
        guard definition.highlighterKind == .treeSitter,
              let resourceName = definition.treeSitterResourceName else {
            return nil
        }

        switch languageID {
        case .swift:
            return LanguageConfiguration(resourceName: resourceName, languagePointer: tree_sitter_swift)
        case .c:
            return LanguageConfiguration(resourceName: resourceName, languagePointer: tree_sitter_c)
        case .cpp:
            return LanguageConfiguration(resourceName: resourceName, languagePointer: tree_sitter_cpp)
        case .json:
            return LanguageConfiguration(resourceName: resourceName, languagePointer: tree_sitter_json)
        case .markdown:
            return LanguageConfiguration(resourceName: resourceName, languagePointer: tree_sitter_markdown)
        case .shell:
            return LanguageConfiguration(resourceName: resourceName, languagePointer: tree_sitter_bash)
        case .plainText, .assembly, .python, .javascript, .typescript, .tsx:
            return nil
        }
    }

    private func incrementalParse(
        fullText: String,
        edit: TextEditDescriptor,
        failedRevision: Int
    ) -> ParseResult? {
        let inputEdit = InputEdit(
            startByte: edit.startUTF16 * 2,
            oldEndByte: edit.oldEndUTF16 * 2,
            newEndByte: edit.newEndUTF16 * 2,
            startPoint: .zero,
            oldEndPoint: .zero,
            newEndPoint: .zero
        )

        let previousTree = tree
        previousTree?.edit(inputEdit)

        guard let newTree = parser.parse(tree: previousTree, string: fullText) else {
            AppLog.syntax.error("Incremental re-parse failed for revision \(failedRevision, privacy: .public); preserving last valid tree.")
            pendingRetryUTF16Ranges.append(
                NSRange(location: edit.startUTF16, length: max(0, edit.newEndUTF16 - edit.startUTF16))
            )
            if let tree { return ParseResult(tree: tree, changedUTF16Ranges: []) }
            return nil
        }

        var changedUTF16Ranges: [NSRange] = []
        if let previousTree {
            changedUTF16Ranges = newTree.changedRanges(from: previousTree).map { $0.bytes.range }
