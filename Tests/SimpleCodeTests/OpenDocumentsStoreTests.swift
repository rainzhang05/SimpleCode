import AppKit
import Foundation
import Testing
@testable import SimpleCode

@Suite(.serialized)
@MainActor
struct OpenDocumentsStoreTests {
    private actor StaticLargeFileLoader: FileContentLoading {
        let text: String
        let openPolicy: FileSizeThresholds.OpenPolicy

        init(text: String, openPolicy: FileSizeThresholds.OpenPolicy = .warnLargeFile) {
            self.text = text
            self.openPolicy = openPolicy
        }

        func metadata(for url: URL) -> FileMetadata {
            FileMetadata(byteCount: Int64(text.utf8.count), openPolicy: openPolicy)
        }

        func load(url: URL, choice: LargeFileOpenChoice?) -> LoadedFileContent {
            LoadedFileContent(
                text: text,
                encoding: .utf8,
                hadBOM: false,
                lineEnding: .lf,
                byteCount: Int64(text.utf8.count),
                modificationDate: nil,
                fileResourceIdentifier: nil,
                language: .swift,
                openPolicy: openPolicy
            )
        }
    }

    private actor PriorityInitialHighlighter: SyntaxHighlighter {
        private var fullLoadCount = 0
        private var priorityLoadCount = 0
        private var remainderLoadCount = 0
        private var lastPriorityRange: NSRange?

        func snapshot() -> (full: Int, priority: Int, remainder: Int, range: NSRange?) {
            (fullLoadCount, priorityLoadCount, remainderLoadCount, lastPriorityRange)
        }

        func load(text: String, revision: Int) -> HighlightBatch {
            fullLoadCount += 1
            return HighlightBatch(
                revision: revision,
                coveredRanges: [NSRange(location: 0, length: text.utf16.count)],
                tokens: [SyntaxToken(range: NSRange(location: 0, length: min(3, text.utf16.count)), category: .keyword)]
            )
        }

        func prepareInitial(
            text: String,
            revision: Int,
            priorityUTF16Range: NSRange
        ) -> InitialHighlightPage {
            priorityLoadCount += 1
            lastPriorityRange = priorityUTF16Range
            let remaining = InitialHighlightPaging.remainingRanges(
                documentLength: text.utf16.count,
                excluding: priorityUTF16Range
            )
            return InitialHighlightPage(
                batch: HighlightBatch(
                    revision: revision,
                    coveredRanges: [priorityUTF16Range],
                    tokens: [SyntaxToken(range: NSRange(location: 0, length: min(3, priorityUTF16Range.length)), category: .keyword)]
                ),
                next: remaining.isEmpty
                    ? nil
                    : InitialHighlightCursor(generation: 1, revision: revision, remainingRanges: remaining)
            )
        }

        func continueInitial(
            _ cursor: InitialHighlightCursor,
            pageSizeUTF16: Int
        ) -> InitialHighlightPage? {
            remainderLoadCount += 1
            return InitialHighlightPage(
                batch: HighlightBatch(
                    revision: cursor.revision,
                    coveredRanges: [cursor.remainingRanges[0]],
                    tokens: []
                ),
                next: nil
            )
        }

        func applyEdit(
            fullText: String,
            edit: TextEditDescriptor,
            revision: Int,
            priorityUTF16Range: NSRange
        ) -> (priority: HighlightBatch, remainder: HighlightBatch?) {
            (load(text: fullText, revision: revision), nil)
        }

        func scheduleViewport(
            fullText: String,
            revision: Int,
            visibleUTF16Range: NSRange
        ) -> (priority: HighlightBatch, remainder: HighlightBatch?) {
            (
                HighlightBatch(revision: revision, coveredRanges: [visibleUTF16Range], tokens: []),
                nil
            )
        }
    }

    private actor ControlledHighlighter: SyntaxHighlighter {
        private let category: SyntaxCategory
        private let suspendsLoad: Bool
        private var didStartLoad = false
        private var startWaiters: [CheckedContinuation<Void, Never>] = []
        private var loadContinuation: CheckedContinuation<Void, Never>?

        init(category: SyntaxCategory = .keyword, suspendsLoad: Bool) {
            self.category = category
            self.suspendsLoad = suspendsLoad
        }

        func waitUntilLoadStarts() async {
            if didStartLoad { return }
            await withCheckedContinuation { continuation in
                startWaiters.append(continuation)
            }
        }

        func resumeLoad() {
            loadContinuation?.resume()
            loadContinuation = nil
        }

        func load(text: String, revision: Int) async -> HighlightBatch {
            didStartLoad = true
            let waiters = startWaiters
            startWaiters.removeAll()
            waiters.forEach { $0.resume() }
            if suspendsLoad {
                await withCheckedContinuation { continuation in
                    loadContinuation = continuation
                }
            }
            let length = min(3, text.utf16.count)
            return HighlightBatch(
                revision: revision,
                coveredRanges: [NSRange(location: 0, length: text.utf16.count)],
                tokens: length > 0
                    ? [SyntaxToken(range: NSRange(location: 0, length: length), category: category)]
                    : []
            )
        }

        func applyEdit(
            fullText: String,
            edit: TextEditDescriptor,
            revision: Int,
            priorityUTF16Range: NSRange
        ) async -> (priority: HighlightBatch, remainder: HighlightBatch?) {
            (await load(text: fullText, revision: revision), nil)
        }

        func scheduleViewport(
            fullText: String,
            revision: Int,
            visibleUTF16Range: NSRange
        ) async -> (priority: HighlightBatch, remainder: HighlightBatch?) {
            (await load(text: fullText, revision: revision), nil)
        }
    }

    private actor DeferredFileContentLoader: FileContentLoading {
        private var continuations: [URL: CheckedContinuation<LoadedFileContent, Error>] = [:]

        func metadata(for url: URL) throws -> FileMetadata {
            FileMetadata(byteCount: 64, openPolicy: .normal)
        }

        func load(url: URL, choice: LargeFileOpenChoice?) async throws -> LoadedFileContent {
            try await withCheckedThrowingContinuation { continuation in
                continuations[url] = continuation
            }
        }

        func hasPendingLoad(for url: URL) -> Bool {
            continuations[url] != nil
        }

        func resolve(_ url: URL, text: String) {
            let content = LoadedFileContent(
                text: text,
                encoding: .utf8,
                hadBOM: false,
                lineEnding: .lf,
                byteCount: Int64(text.utf8.count),
                modificationDate: nil,
                fileResourceIdentifier: nil,
                language: LanguageDetector.detect(url: url, content: text),
                openPolicy: .normal
            )
            continuations.removeValue(forKey: url)?.resume(returning: content)
        }
    }

    @Test func duplicateOpenActivatesExistingTab() async throws {
        let store = OpenDocumentsStore()
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("A.swift")
        try "let a = 1".write(to: file, atomically: true, encoding: .utf8)

        await store.open(url: file)
        let firstID = store.activeSessionID
        await store.open(url: file)
        #expect(store.sessions.count == 1)
        #expect(store.activeSessionID == firstID)
    }

    @Test func dirtyStateTransitions() async throws {
        let session = EditorDocumentSession(displayName: "T.swift")
        session.textStorage.setAttributedString(NSAttributedString(string: "x"))
        #expect(!session.isDirty)
        session.markDirty()
        #expect(session.isDirty)
    }

    @Test func reopenRecentlyClosed() async throws {
        let store = OpenDocumentsStore()
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Closed.swift")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        await store.open(url: file)
        let id = store.activeSessionID!
        _ = store.close(sessionID: id, force: true)
        await store.reopenLastClosed()
        #expect(store.sessions.count == 1)
    }

    @Test func loadedSwiftDocumentPublishesWithInitialSyntaxAlreadyApplied() async throws {
        let store = OpenDocumentsStore()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Prepared.swift")
        try "let answer = 42\n".write(to: file, atomically: true, encoding: .utf8)

        await store.open(url: file)

        let session = try #require(store.activeSession)
        #expect(session.loadState == .loaded)
        #expect(session.highlighter != nil)
        #expect(session.hasAppliedSyntaxHighlighting)
        let keywordColor = session.textStorage.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor
        #expect(keywordColor != nil)
        #expect(keywordColor != ColorRole.editorForegroundNSColor)
    }

    @Test func loadedPublicationWaitsForSyntaxAndUsesAdaptiveTokenColor() async throws {
        let highlighter = ControlledHighlighter(suspendsLoad: true)
        let store = OpenDocumentsStore(highlighterFactory: { _ in highlighter })
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Boundary.swift")
        try "let boundary = true\n".write(to: file, atomically: true, encoding: .utf8)

        let openTask = Task { await store.open(url: file) }
        await highlighter.waitUntilLoadStarts()

        let loadingSession = try #require(store.activeSession)
        #expect(loadingSession.loadState == .loading)
        #expect(!loadingSession.hasAppliedSyntaxHighlighting)

        await highlighter.resumeLoad()
        await openTask.value

        let loadedSession = try #require(store.activeSession)
        #expect(loadedSession.loadState == .loaded)
        #expect(loadedSession.hasAppliedSyntaxHighlighting)
        let tokenColor = try #require(loadedSession.textStorage.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor)
        #expect(tokenColor != ColorRole.editorForegroundNSColor)
        let expectedPair = SyntaxPaletteDefaults.keyword
        try expect(tokenColor, resolvesLike: expectedPair)
    }

    @Test func largeFilePublishesAfterPrioritySyntaxAndDefersRemainder() async throws {
        let text = String(repeating: "let visible = true\n", count: 8_000)
        let loader = StaticLargeFileLoader(text: text)
        let highlighter = PriorityInitialHighlighter()
        let store = OpenDocumentsStore(loader: loader, highlighterFactory: { _ in highlighter })
        let file = FileManager.default.temporaryDirectory.appending(path: "LargePriority-\(UUID().uuidString).swift")

        await store.open(url: file, choice: .openAnyway)

        let session = try #require(store.activeSession)
        let calls = await highlighter.snapshot()
        let priorityRange = try #require(calls.range)
        #expect(session.loadState == .loaded)
        #expect(session.hasAppliedSyntaxHighlighting)
        #expect(calls.full == 0)
        #expect(calls.priority == 1)
        #expect(calls.remainder == 0)
        #expect(priorityRange.location == 0)
        #expect(priorityRange.length < text.utf16.count)
        #expect(session.deferredInitialHighlightCursor != nil)
        #expect(session.textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) != nil)
    }

    @Test func normalPolicyDocumentLargerThanOnePageAlsoPublishesVisibleSyntaxFirst() async throws {
        let text = String(repeating: "let responsive = true\n", count: 8_000)
        let loader = StaticLargeFileLoader(text: text, openPolicy: .normal)
        let highlighter = PriorityInitialHighlighter()
        let store = OpenDocumentsStore(loader: loader, highlighterFactory: { _ in highlighter })
        let file = FileManager.default.temporaryDirectory
            .appending(path: "NormalPriority-\(UUID().uuidString).swift")

        await store.open(url: file)

        let session = try #require(store.activeSession)
        let calls = await highlighter.snapshot()
        #expect(session.loadState == .loaded)
        #expect(calls.full == 0)
        #expect(calls.priority == 1)
        #expect(session.deferredInitialHighlightCursor != nil)
    }

    @Test func largeReloadPrioritizesLastVisibleRangeInsteadOfCaret() async throws {
        let text = String(repeating: "let visible = true\n", count: 10_000)
        let loader = StaticLargeFileLoader(text: text)
        let highlighter = PriorityInitialHighlighter()
        let store = OpenDocumentsStore(loader: loader, highlighterFactory: { _ in highlighter })
        let file = FileManager.default.temporaryDirectory.appending(path: "LargeReload-\(UUID().uuidString).swift")

        await store.open(url: file, choice: .openAnyway)
        let session = try #require(store.activeSession)
        session.selectionRange = NSRange(location: 0, length: 0)
        let visibleRange = NSRange(location: text.utf16.count * 3 / 4, length: 2_000)
        session.recordVisibleUTF16Range(visibleRange)

        await store.reloadFromDisk(session: session)

        let calls = await highlighter.snapshot()
        let priorityRange = try #require(calls.range)
        let visibleMidpoint = visibleRange.location + visibleRange.length / 2
        #expect(calls.priority == 2)
        #expect(NSLocationInRange(visibleMidpoint, priorityRange))
        #expect(!NSLocationInRange(session.selectionRange.location, priorityRange))
    }

    @Test func staleInitialHighlightRetriesCurrentLanguageBeforePublishing() async throws {
        let firstHighlighter = ControlledHighlighter(suspendsLoad: true)
        let retryHighlighter = ControlledHighlighter(category: .string, suspendsLoad: false)
        var factoryCalls = 0
        let store = OpenDocumentsStore(highlighterFactory: { _ in
            factoryCalls += 1
            return factoryCalls == 1 ? firstHighlighter : retryHighlighter
        })
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Revision.swift")
        try "let revision = true\n".write(to: file, atomically: true, encoding: .utf8)

        let openTask = Task { await store.open(url: file) }
        await firstHighlighter.waitUntilLoadStarts()
        let session = try #require(store.activeSession)
        session.setLanguageOverride(.python)
        await firstHighlighter.resumeLoad()
        await openTask.value

        #expect(session.loadState == .loaded)
        #expect(session.language == .python)
        #expect(session.hasAppliedSyntaxHighlighting)
        #expect(factoryCalls == 2)
    }

    @Test func recentlyClosedRecordDoesNotRetainTheEditorSession() async throws {
        let store = OpenDocumentsStore()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Closed.swift")
        try "let closed = true\n".write(to: file, atomically: true, encoding: .utf8)
        await store.open(url: file)

        weak var releasedSession: EditorDocumentSession?
        let closedID: UUID
        do {
            let session = try #require(store.activeSession)
            releasedSession = session
            closedID = session.id
        }

        #expect(store.close(sessionID: closedID, force: true))
        #expect(store.recentlyClosed.count == 1)
        #expect(releasedSession == nil)

        await store.reopenLastClosed()
        #expect(store.activeSession?.fileURL?.standardizedFileURL == file.standardizedFileURL)
    }

    @Test func reloadSyntaxFailureReleasesHighlighterResources() async throws {
        let firstHighlighter = ControlledHighlighter(suspendsLoad: false)
        var factoryCalls = 0
        let store = OpenDocumentsStore(highlighterFactory: { _ in
            factoryCalls += 1
            return factoryCalls == 1 ? firstHighlighter : nil
        })
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Reload.swift")
        try "let original = true\n".write(to: file, atomically: true, encoding: .utf8)

        await store.open(url: file)
        let session = try #require(store.activeSession)
        #expect(session.highlighter != nil)
        try "let reloaded = false\n".write(to: file, atomically: true, encoding: .utf8)

        await store.reloadFromDisk(session: session)

        #expect(session.loadState == .error("Could not prepare syntax highlighting."))
        #expect(session.highlighter == nil)
        #expect(!session.hasAppliedSyntaxHighlighting)
    }

    @Test func supersededReopenKeepsRecentlyClosedRecord() async throws {
        let loader = DeferredFileContentLoader()
        let store = OpenDocumentsStore(loader: loader)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let closedFile = directory.appendingPathComponent("Closed.swift")
        let replacementFile = directory.appendingPathComponent("Replacement.swift")

        let initialOpen = Task { @MainActor in await store.open(url: closedFile) }
        await waitForPendingLoad(of: closedFile, in: loader)
        await loader.resolve(closedFile, text: "let closed = true")
        await initialOpen.value
        let closedSession = try #require(store.activeSession)
        #expect(store.close(sessionID: closedSession.id, force: true))
        #expect(store.recentlyClosed.first?.fileURL == closedFile)

        let reopen = Task { @MainActor in await store.reopenLastClosed() }
        await waitForPendingLoad(of: closedFile, in: loader)
        let replacementOpen = Task { @MainActor in await store.open(url: replacementFile) }
        await waitForPendingLoad(of: replacementFile, in: loader)
        await loader.resolve(closedFile, text: "let closed = true")
        await loader.resolve(replacementFile, text: "let replacement = true")
        await reopen.value
        await replacementOpen.value

        #expect(store.activeSession?.fileURL == replacementFile)
        #expect(store.recentlyClosed.first?.fileURL == closedFile)
    }

    @Test func rapidFileSelectionKeepsOnlyTheLatestOpenRequest() async throws {
        let loader = DeferredFileContentLoader()
        let store = OpenDocumentsStore(loader: loader)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let first = directory.appendingPathComponent("First.swift")
        let second = directory.appendingPathComponent("Second.swift")

        let firstTask = Task { @MainActor in await store.open(url: first) }
        await waitForPendingLoad(of: first, in: loader)
        let secondTask = Task { @MainActor in await store.open(url: second) }
        await waitForPendingLoad(of: second, in: loader)

        await loader.resolve(first, text: "let first = 1")
        await loader.resolve(second, text: "let second = 2")
        await firstTask.value
        await secondTask.value

        #expect(store.sessions.count == 1)
        #expect(store.activeSession?.fileURL?.standardizedFileURL == second.standardizedFileURL)
        #expect(store.activeSession?.textStorage.string == "let second = 2")
    }

    private func waitForPendingLoad(of url: URL, in loader: DeferredFileContentLoader) async {
        for _ in 0..<100 {
            if await loader.hasPendingLoad(for: url) { return }
            await Task.yield()
        }
        Issue.record("Timed out waiting for deferred file load")
    }

    private func expect(_ color: NSColor, resolvesLike pair: ColorRolePair) throws {
        for (appearanceName, expected) in [(NSAppearance.Name.aqua, pair.light), (.darkAqua, pair.dark)] {
            let appearance = try #require(NSAppearance(named: appearanceName))
            var resolved: NSColor?
            appearance.performAsCurrentDrawingAppearance {
                resolved = color.usingColorSpace(.sRGB)
            }
            let actual = try #require(resolved)
            let expectedRGB = try #require(expected.usingColorSpace(.sRGB))
            #expect(abs(actual.redComponent - expectedRGB.redComponent) < 0.000_1)
            #expect(abs(actual.greenComponent - expectedRGB.greenComponent) < 0.000_1)
            #expect(abs(actual.blueComponent - expectedRGB.blueComponent) < 0.000_1)
        }
    }
}
