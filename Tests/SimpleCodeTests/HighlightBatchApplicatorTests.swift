import Foundation
import Testing
@testable import SimpleCode

struct HighlightBatchApplicatorTests {
    @Test func staleBatchIsRejected() {
        #expect(!HighlightBatchApplicator.shouldApply(batchRevision: 1, currentRevision: 2))
    }

    @Test func currentBatchIsAccepted() {
        #expect(HighlightBatchApplicator.shouldApply(batchRevision: 3, currentRevision: 3))
    }
}
