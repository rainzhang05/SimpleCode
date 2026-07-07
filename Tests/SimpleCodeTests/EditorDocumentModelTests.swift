import Testing
@testable import SimpleCode

@Suite(.serialized)
@MainActor
struct EditorDocumentModelTests {
    @Test func revisionStartsAtZero() {
        let document = EditorDocumentModel()
        #expect(document.revision == 0)
    }

    @Test func revisionIncrementsMonotonicallyOnEachEdit() {
        let document = EditorDocumentModel()

        let first = document.bumpRevision()
        let second = document.bumpRevision()
        let third = document.bumpRevision()

        #expect(first == 1)
        #expect(second == 2)
        #expect(third == 3)
        #expect(document.revision == 3)
    }

    /// Mirrors the exact guard `CodeEditorRepresentable.Coordinator.apply(batch:)`
    /// uses to reject stale asynchronous highlighting results: a batch is only
    /// applied if the revision it was computed for still matches the document's
    /// current revision.
    @Test func aBatchComputedForAnOlderRevisionIsConsideredStale() {
        let document = EditorDocumentModel()

        let revisionAtScheduleTime = document.bumpRevision()
        _ = document.bumpRevision()

        #expect(!HighlightBatchApplicator.shouldApply(
            batchRevision: revisionAtScheduleTime,
            currentRevision: document.revision
        ))
    }

    @Test func aBatchComputedForTheCurrentRevisionIsNotStale() {
        let document = EditorDocumentModel()

        let revisionAtScheduleTime = document.bumpRevision()

        #expect(HighlightBatchApplicator.shouldApply(
            batchRevision: revisionAtScheduleTime,
            currentRevision: document.revision
        ))
    }
}
