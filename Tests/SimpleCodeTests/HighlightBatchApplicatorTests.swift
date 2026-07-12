import AppKit
import Testing
@testable import SimpleCode

struct HighlightBatchApplicatorTests {
    @Test func staleBatchIsRejected() {
        #expect(!HighlightBatchApplicator.shouldApply(batchRevision: 1, currentRevision: 2))
    }

    @Test func currentBatchIsAccepted() {
        #expect(HighlightBatchApplicator.shouldApply(batchRevision: 3, currentRevision: 3))
    }

    @Test func consecutiveParserRevisionUsesIncrementalEdit() {
        #expect(HighlightBatchApplicator.parseStrategy(
            lastParsedRevision: 4,
            requestedRevision: 5
        ) == .incremental)
    }

    @Test func missingOrSkippedParserRevisionRequiresFullParse() {
        #expect(HighlightBatchApplicator.parseStrategy(
            lastParsedRevision: nil,
            requestedRevision: 1
        ) == .full)
        #expect(HighlightBatchApplicator.parseStrategy(
            lastParsedRevision: 2,
            requestedRevision: 4
        ) == .full)
    }

    @MainActor
    @Test func atomicBatchOnlyResetsItsCoveredRange() throws {
        let storage = NSTextStorage(string: "let x = value")
        storage.addAttribute(.foregroundColor, value: NSColor.orange, range: NSRange(location: 0, length: storage.length))
        let batch = HighlightBatch(
            revision: 1,
            coveredRanges: [NSRange(location: 0, length: 5)],
            tokens: [SyntaxToken(range: NSRange(location: 0, length: 3), category: .keyword)]
        )

        HighlightBatchApplicator.apply(batch, to: storage)

        let outside = try #require(storage.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor)
        #expect(outside == .orange)
        let token = try #require(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        #expect(token != .orange)
    }
}
