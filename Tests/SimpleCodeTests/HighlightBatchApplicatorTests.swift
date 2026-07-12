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

    @Test func initialPriorityPageStaysBoundedForOneLongLine() {
        let text = String(repeating: "x", count: InitialHighlightPaging.pageSizeUTF16 * 3)
        let requestedOffset = InitialHighlightPaging.pageSizeUTF16 * 2

        let range = InitialHighlightPaging.priorityRange(
            in: text,
            aroundUTF16Offset: requestedOffset
        )

        #expect(range.length <= InitialHighlightPaging.pageSizeUTF16)
        #expect(range.length < text.utf16.count)
        #expect(NSLocationInRange(requestedOffset, range))
    }

    @Test func initialPagesPartitionDocumentWithoutGaps() throws {
        let text = String(repeating: "let page = true\n", count: 12_000)
        let priority = InitialHighlightPaging.priorityRange(
            in: text,
            aroundUTF16Offset: text.utf16.count / 2
        )
        let remaining = InitialHighlightPaging.remainingRanges(
            documentLength: text.utf16.count,
            excluding: priority
        )
        var cursor: InitialHighlightCursor? = InitialHighlightCursor(
            generation: 1,
            revision: 0,
            remainingRanges: remaining
        )
        var pages = [priority]

        while let current = cursor {
            let page = try #require(InitialHighlightPaging.nextPageRange(
                in: text,
                cursor: current,
                pageSizeUTF16: InitialHighlightPaging.pageSizeUTF16
            ))
            pages.append(page)
            cursor = InitialHighlightPaging.advancing(current, past: page)
        }

        let sorted = pages.sorted { $0.location < $1.location }
        #expect(sorted.first?.location == 0)
        #expect(sorted.last.map(NSMaxRange) == text.utf16.count)
        for pair in zip(sorted, sorted.dropFirst()) {
            #expect(NSMaxRange(pair.0) == pair.1.location)
        }
    }
}
