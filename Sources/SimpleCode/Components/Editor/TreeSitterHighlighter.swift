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
    private var lastParsedText = ""
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
        lastParsedText = text
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
        let priorityRanges = mergedRanges(
            [priorityUTF16Range, editPointRange],
            documentLength: fullText.utf16.count
        )

        let parseResult = incrementalParse(fullText: fullText, edit: edit, failedRevision: revision)
        guard let parseResult else {
            return (
                HighlightBatch(revision: revision, coveredRanges: priorityRanges, tokens: []),
                nil
            )
        }

        return batches(
            tree: parseResult.tree,
            changedUTF16Ranges: parseResult.changedUTF16Ranges,
            revision: revision,
            priorityUTF16Ranges: priorityRanges,
            documentUTF16Count: fullText.utf16.count,
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
            priorityUTF16Ranges: mergedRanges([visibleUTF16Range], documentLength: fullText.utf16.count),
            documentUTF16Count: fullText.utf16.count,
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
        let previousText = lastParsedText
        let inputEdit = InputEdit(
            startByte: edit.startUTF16 * 2,
            oldEndByte: edit.oldEndUTF16 * 2,
            newEndByte: edit.newEndUTF16 * 2,
            startPoint: point(atUTF16Offset: edit.startUTF16, in: previousText),
            oldEndPoint: point(atUTF16Offset: edit.oldEndUTF16, in: previousText),
            newEndPoint: point(atUTF16Offset: edit.newEndUTF16, in: fullText)
        )

        let previousTree = tree
        previousTree?.edit(inputEdit)

        guard let newTree = parser.parse(tree: previousTree, string: fullText) else {
            // An incremental failure must not leave the actor holding a tree whose
            // offsets no longer match the source. A bounded full parse restores a
            // coherent base for the next keystroke instead of accumulating invalid
            // edits and eventually painting stale tokens.
            AppLog.syntax.error("Incremental re-parse failed for revision \(failedRevision, privacy: .public); rebuilding the parser tree.")
            guard let rebuiltTree = parser.parse(fullText) else {
                tree = nil
                lastParsedText = ""
                pendingRetryUTF16Ranges.append(
                    NSRange(location: edit.startUTF16, length: max(0, edit.newEndUTF16 - edit.startUTF16))
                )
                return nil
            }
            tree = rebuiltTree
            lastParsedText = fullText
            return ParseResult(
                tree: rebuiltTree,
                changedUTF16Ranges: [NSRange(location: 0, length: fullText.utf16.count)]
            )
        }

        var changedUTF16Ranges: [NSRange] = []
        if let previousTree {
            changedUTF16Ranges = newTree.changedRanges(from: previousTree).map { $0.bytes.range }
        }

        tree = newTree
        lastParsedText = fullText
        return ParseResult(tree: newTree, changedUTF16Ranges: changedUTF16Ranges)
    }

    private func batches(
        tree: MutableTree,
        changedUTF16Ranges: [NSRange],
        revision: Int,
        priorityUTF16Ranges: [NSRange],
        documentUTF16Count: Int,
        includePendingRetry: Bool
    ) -> (priority: HighlightBatch, remainder: HighlightBatch?) {
        var priorityTokens: [SyntaxToken] = []
        for range in priorityUTF16Ranges {
            let priorityByteRange = utf16RangeToByteRange(range, documentUTF16Count: documentUTF16Count)
            priorityTokens.append(contentsOf: highlightTokens(in: tree, restrictedTo: priorityByteRange))
        }
        let priorityBatch = HighlightBatch(
            revision: revision,
            coveredRanges: priorityUTF16Ranges,
            tokens: priorityTokens
        )

        var remainderRanges: [NSRange] = changedUTF16Ranges
            .filter { changedRange in
                !priorityUTF16Ranges.contains { intersectsUTF16(changedRange, $0) }
            }

        if includePendingRetry, !pendingRetryUTF16Ranges.isEmpty {
            remainderRanges.append(contentsOf: pendingRetryUTF16Ranges.filter { pendingRange in
                !priorityUTF16Ranges.contains { intersectsUTF16(pendingRange, $0) }
            })
            pendingRetryUTF16Ranges.removeAll()
        }

        remainderRanges = mergedRanges(remainderRanges, documentLength: documentUTF16Count)

        guard !remainderRanges.isEmpty else {
            return (priorityBatch, nil)
        }

        var remainderTokens: [SyntaxToken] = []
        for range in remainderRanges {
            let byteRange = utf16RangeToByteRange(range, documentUTF16Count: documentUTF16Count)
            remainderTokens.append(contentsOf: highlightTokens(in: tree, restrictedTo: byteRange))
        }

        let remainderBatch = HighlightBatch(
            revision: revision,
            coveredRanges: remainderRanges,
            tokens: remainderTokens
        )
        return (priorityBatch, remainderBatch)
    }

    private func highlightTokens(in tree: MutableTree, restrictedTo byteRange: Range<UInt32>?) -> [SyntaxToken] {
        guard let root = tree.rootNode else { return [] }

        let cursor = query.execute(node: root, in: tree)
        if let byteRange {
            cursor.setByteRange(range: byteRange)
        }

        var tokens: [SyntaxToken] = []
        while let capture = cursor.nextCapture() {
            guard let name = capture.name, let category = HighlightTheme.category(forCapture: name) else {
                continue
            }
            tokens.append(SyntaxToken(range: capture.range, category: category))
        }
        return tokens
    }

    private func utf16RangeToByteRange(_ range: NSRange, documentUTF16Count: Int) -> Range<UInt32> {
        let lower = UInt32(max(0, range.location) * 2)
        let upper = UInt32(min(documentUTF16Count, NSMaxRange(range)) * 2)
        return lower..<max(lower + 2, upper)
    }

    private func intersectsUTF16(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
        NSIntersectionRange(lhs, rhs).length > 0
    }

    private func point(atUTF16Offset offset: Int, in text: String) -> Point {
        let nsText = text as NSString
        let limit = max(0, min(offset, nsText.length))
        var row = 0
        var lineStart = 0
        var index = 0
        while index < limit {
            if nsText.character(at: index) == 10 { // LF; CRLF is one parser line.
                row += 1
                lineStart = index + 1
            }
            index += 1
        }
        // The parser is fed UTF-16LE, so its line-relative column is expressed in
        // bytes rather than Swift/String character offsets.
        return Point(row: row, column: (limit - lineStart) * 2)
    }

    private func mergedRanges(_ ranges: [NSRange], documentLength: Int) -> [NSRange] {
        let clamped = ranges.compactMap { range -> NSRange? in
            let lower = max(0, min(range.location, documentLength))
            let upper = max(lower, min(NSMaxRange(range), documentLength))
            return upper > lower ? NSRange(location: lower, length: upper - lower) : nil
        }.sorted { $0.location < $1.location }

        var merged: [NSRange] = []
        for range in clamped {
            guard var previous = merged.last else {
                merged.append(range)
                continue
            }
            if range.location <= NSMaxRange(previous) {
                previous.length = max(NSMaxRange(previous), NSMaxRange(range)) - previous.location
                merged[merged.count - 1] = previous
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private static func highlightsQueryURL(resourceName: String) -> URL? {
        let bundle = AppResources.bundle
        if let url = bundle.url(
            forResource: resourceName,
            withExtension: "scm",
            subdirectory: "TreeSitterQueries/\(resourceName)"
        ) {
            return url
        }
        return bundle.url(forResource: resourceName, withExtension: "scm")
    }
}

private extension Range where Bound == UInt32 {
    var range: NSRange {
        NSRange(location: Int(lowerBound / 2), length: Int((upperBound - lowerBound) / 2))
    }
}
