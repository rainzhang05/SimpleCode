import Foundation

/// Shared stale-result guard for syntax highlighting batches.
enum HighlightBatchApplicator {
    static func shouldApply(batchRevision: Int, currentRevision: Int) -> Bool {
        batchRevision == currentRevision
    }
}
