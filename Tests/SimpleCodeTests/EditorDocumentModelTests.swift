import Testing
@testable import SimpleCode

struct EditorDocumentModelTests {
    /// Mirrors the exact guard `CodeEditorRepresentable.Coordinator.apply(batch:)`
    /// uses to reject stale asynchronous highlighting results: a batch is only
    /// applied if the revision it was computed for still matches the document's
    /// current revision.
    @Test func aBatchComputedForAnOlderRevisionIsConsideredStale() {
        #expect(!HighlightBatchApplicator.shouldApply(
            batchRevision: 1,
            currentRevision: 2
        ))
    }

    @Test func aBatchComputedForTheCurrentRevisionIsNotStale() {
        #expect(HighlightBatchApplicator.shouldApply(
            batchRevision: 3,
            currentRevision: 3
        ))
    }
}
