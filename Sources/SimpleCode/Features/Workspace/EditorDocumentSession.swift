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
    var enablesSyntaxHighlighting = true
    var highlighter: (any SyntaxHighlighter)?
    private var semanticTokens: [SyntaxToken] = []
    private(set) var syntaxContext: SyntaxContext = .empty

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

    func applyLoadedContent(_ content: LoadedFileContent, url: URL, choice: LargeFileOpenChoice? = nil) {
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
        lineStartIndex.rebuild(from: content.text)
        clearSyntaxContext()
        loadState = .loaded
        isDirty = false
        externalChangeState = .none
        revision = 0
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
