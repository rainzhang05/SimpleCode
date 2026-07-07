import Foundation

/// SwiftUI-facing state for the single open editor document in this phase.
///
/// This model deliberately does **not** hold the document text as a `Binding<String>`
/// that flows back into `CodeTextView`. `NSTextStorage` is the one source of truth for
/// text content; this model only tracks the revision counter used for stale-result
/// rejection and diagnostics. Font size is owned separately by `EditorSettingsStore`
/// and flows one-way into the view — that separation, plus the absence of a text
/// binding, is what guarantees there is no feedback loop between SwiftUI and the text
/// view, and that SwiftUI updates never disturb the cursor position.
@MainActor
@Observable
final class EditorDocumentModel {
    private(set) var revision: Int = 0
    private(set) var cursorLine: Int = 1
    private(set) var cursorColumn: Int = 1

    /// Called once per character-level text-storage edit. Returns the new revision
    /// so the caller can tag the in-flight async highlighting work it is about to
    /// schedule for that edit.
    @discardableResult
    func bumpRevision() -> Int {
        revision += 1
        return revision
    }

    func updateCursor(line: Int, column: Int) {
        cursorLine = max(1, line)
        cursorColumn = max(1, column)
    }
}
