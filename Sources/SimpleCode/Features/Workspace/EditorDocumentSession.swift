import AppKit
import Foundation

enum DocumentLoadState: Equatable {
    case idle
    case loading
    case loaded
    case binaryPlaceholder
    case error(String)
}

@MainActor
@Observable
final class EditorDocumentSession: Identifiable {
    let id: UUID
    private(set) var fileURL: URL?
    private(set) var displayName: String
    private(set) var fileIdentity: FileIdentity?
    let textStorage: NSTextStorage
    /// NSTextView normally inherits one window-wide undo manager. Keeping the
    /// history with its document makes Command-Z deterministic after a tab switch.
    let undoManager = UndoManager()
    var lineStartIndex = LineStartIndex()
    private(set) var revision: Int = 0
    private(set) var cursorLine: Int = 1
    private(set) var cursorColumn: Int = 1
    private(set) var isDirty = false
    private(set) var isReadOnly = false
    private(set) var loadState: DocumentLoadState = .idle
    private(set) var encoding: TextEncodingMode = .utf8
    private(set) var hadBOM = false
    private(set) var lineEnding: LineEndingMode = .lf
    private(set) var language: DocumentLanguage = .plainText
    var languageOverride: LanguageID?
    private(set) var lastKnownModificationDate: Date?
    private(set) var lastKnownByteCount: Int64 = 0
    private(set) var lastKnownResourceID: Data?
    private(set) var hasExternalModification = false
    private(set) var externalChangeState: ExternalChangeState = .none
    var selectionRange = NSRange(location: 0, length: 0)
    var pendingSelectionRange: NSRange?
    var scrollOffset: CGPoint = .zero
    /// Changes whenever the highlighting configuration changes. The AppKit editor
    /// uses this to invalidate work from the previously selected language without
    /// treating a language override as a different document.
    private(set) var syntaxConfigurationRevision = 0
    var enablesSyntaxHighlighting = true {
        didSet {
            guard oldValue != enablesSyntaxHighlighting else { return }
            syntaxConfigurationRevision &+= 1
        }
    }
    var highlighter: (any SyntaxHighlighter)? {
        didSet { syntaxConfigurationRevision &+= 1 }
    }
    private var semanticTokens: [SyntaxToken] = []
    private(set) var deferredInitialHighlightCursor: InitialHighlightCursor?
    private(set) var syntaxContext: SyntaxContext = .empty
    private(set) var didApplySyntaxHighlighting = false

    var hasAppliedSyntaxHighlighting: Bool {
        didApplySyntaxHighlighting
    }

    init(id: UUID = UUID(), displayName: String = "Untitled", fileURL: URL? = nil) {
        self.id = id
        self.displayName = displayName
        self.fileURL = fileURL
        if let fileURL {
            self.fileIdentity = FileIdentity(url: fileURL)
        }
        self.textStorage = NSTextStorage()
    }

    var isUntitled: Bool { fileURL == nil }

    @discardableResult
    func bumpRevision() -> Int {
        revision += 1
        return revision
    }

    func updateCursor(line: Int, column: Int) {
        cursorLine = max(1, line)
        cursorColumn = max(1, column)
    }

    func markDirty() {
        isDirty = true
    }

    func markClean(snapshot: (Date?, Int64, Data?)? = nil) {
        isDirty = false
        hasExternalModification = false
        externalChangeState = .none
        if let snapshot {
            lastKnownModificationDate = snapshot.0
            lastKnownByteCount = snapshot.1
            lastKnownResourceID = snapshot.2
        }
    }

    /// Installs decoded content while deliberately keeping the session out of the
    /// published `.loaded` state. The store can prepare syntax attributes before a
    /// visible editor is created, avoiding a monochrome first frame.
    func prepareLoadedContent(_ content: LoadedFileContent, url: URL, choice: LargeFileOpenChoice? = nil) {
        loadState = .loading
        fileURL = url
        fileIdentity = FileIdentity(url: url)
        displayName = url.lastPathComponent
        encoding = content.encoding
        hadBOM = content.hadBOM
        lineEnding = content.lineEnding
        language = content.language
        lastKnownModificationDate = content.modificationDate
        lastKnownByteCount = content.byteCount
        lastKnownResourceID = content.fileResourceIdentifier
        switch choice {
        case .openReadOnlyWithoutSyntax:
            isReadOnly = true
            enablesSyntaxHighlighting = false
        case .openWithoutSyntax:
            isReadOnly = false
            enablesSyntaxHighlighting = false
        case .openAnyway:
            isReadOnly = false
            enablesSyntaxHighlighting = LanguageRegistry.definition(for: content.language).highlightingAvailable
        case .openNormally, .cancel, nil:
            isReadOnly = content.openPolicy == .readOnlyRecommended && choice == nil
            enablesSyntaxHighlighting = LanguageRegistry.definition(for: content.language).highlightingAvailable && !isReadOnly
        }
        textStorage.setAttributedString(NSAttributedString(string: content.text))
        undoManager.removeAllActions()
        lineStartIndex.rebuild(from: content.text)
        clearSyntaxContext()
        isDirty = false
        externalChangeState = .none
        revision = 0
    }

    func applyInitialHighlighting(_ batch: HighlightBatch) {
        guard batch.revision == revision else { return }
        HighlightBatchApplicator.apply(batch, to: textStorage)
        mergeSyntaxTokens(batch.tokens, replacingCoveredRanges: batch.coveredRanges)
    }

    func deferInitialHighlighting(_ cursor: InitialHighlightCursor?) {
        deferredInitialHighlightCursor = cursor
    }

    func advanceDeferredInitialHighlighting(
        from cursor: InitialHighlightCursor,
        to next: InitialHighlightCursor?
    ) {
        guard deferredInitialHighlightCursor == cursor else { return }
        deferredInitialHighlightCursor = next
    }

    func refreshSyntaxAttributes() {
        guard didApplySyntaxHighlighting else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        HighlightBatchApplicator.apply(
            HighlightBatch(revision: revision, coveredRanges: [fullRange], tokens: semanticTokens),
            to: textStorage
        )
    }

    func publishLoadedContent() {
        loadState = .loaded
    }

    func applyLoadedContent(_ content: LoadedFileContent, url: URL, choice: LargeFileOpenChoice? = nil) {
        prepareLoadedContent(content, url: url, choice: choice)
        publishLoadedContent()
    }

    func setBinaryPlaceholder(url: URL, byteCount: Int64) {
        fileURL = url
        fileIdentity = FileIdentity(url: url)
        displayName = url.lastPathComponent
        lastKnownByteCount = byteCount
        loadState = .binaryPlaceholder
        isReadOnly = true
        enablesSyntaxHighlighting = false
    }

    func setLoadError(_ message: String, url: URL?) {
        if let url {
            fileURL = url
            displayName = url.lastPathComponent
            fileIdentity = FileIdentity(url: url)
        }
        loadState = .error(message)
        enablesSyntaxHighlighting = false
        releaseSyntaxResources()
    }

    func setLoading() {
        loadState = .loading
    }

    func updateFileURL(_ url: URL) {
        fileURL = url
        fileIdentity = FileIdentity(url: url)
        displayName = url.lastPathComponent
    }

    func noteExternalModification() {
        hasExternalModification = true
    }

    func setExternalChangeState(_ state: ExternalChangeState) {
        externalChangeState = state
        hasExternalModification = state != .none
    }

    func dismissExternalChange() {
        externalChangeState = .none
        hasExternalModification = false
    }

    func reloadFromDisk(_ content: LoadedFileContent) {
        applyLoadedContent(content, url: fileURL!)
    }

    func setLanguageOverride(_ id: LanguageID) {
        languageOverride = id
        language = id
        enablesSyntaxHighlighting = LanguageRegistry.definition(for: id).highlightingAvailable && !isReadOnly
        highlighter = enablesSyntaxHighlighting ? HighlightProviderFactory.makeHighlighter(for: id) : nil
        clearSyntaxContext()
        bumpRevision()
    }

    func configureSampleContent(text: String) {
        textStorage.setAttributedString(NSAttributedString(string: text))
        lineStartIndex.rebuild(from: text)
        language = .swift
        loadState = .loaded
        enablesSyntaxHighlighting = true
        highlighter = HighlightProviderFactory.makeHighlighter(for: .swift)
        clearSyntaxContext()
    }

    func mergeSyntaxTokens(_ tokens: [SyntaxToken], replacingCoveredRanges coveredRanges: [NSRange]) {
        if coveredRanges.contains(where: { $0.location == 0 && $0.length >= textStorage.length }) {
            semanticTokens = tokens
            deferredInitialHighlightCursor = nil
        } else {
            semanticTokens.removeAll { token in
                coveredRanges.contains { NSIntersectionRange(token.range, $0).length > 0 }
            }
            semanticTokens.append(contentsOf: tokens)
        }
        didApplySyntaxHighlighting = true
        rebuildSyntaxContext()
    }

    func clearSyntaxContext() {
        semanticTokens = []
        deferredInitialHighlightCursor = nil
        syntaxContext = .empty
        didApplySyntaxHighlighting = false
    }

    func releaseSyntaxResources() {
        highlighter = nil
        clearSyntaxContext()
    }

    func applySavedText(_ text: String) {
        textStorage.setAttributedString(NSAttributedString(string: text))
        undoManager.removeAllActions()
        lineStartIndex.rebuild(from: text)
        let clampedLocation = min(selectionRange.location, textStorage.length)
        let maxLength = max(0, textStorage.length - clampedLocation)
        selectionRange = NSRange(location: clampedLocation, length: min(selectionRange.length, maxLength))
        pendingSelectionRange = selectionRange
        clearSyntaxContext()
    }

    private func rebuildSyntaxContext() {
        let stringRanges = semanticTokens
            .filter { $0.category == .string }
            .map(\.range)
        let commentRanges = semanticTokens
            .filter { $0.category == .comment || $0.category == .documentationComment }
            .map(\.range)
        syntaxContext = SyntaxContext(stringRanges: stringRanges, commentRanges: commentRanges)
    }
}
