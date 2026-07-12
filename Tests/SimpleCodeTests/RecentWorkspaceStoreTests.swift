import Foundation
import Testing
@testable import SimpleCode

@Suite(.serialized)
@MainActor
struct RecentWorkspaceStoreTests {
    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "com.simplecode.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SimpleCodeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func recordingANewFolderCreatesEntryWithGeneratedUUID() throws {
        let store = RecentWorkspaceStore(defaults: makeIsolatedDefaults())
        let folder = try makeTemporaryDirectory()

        let record = store.recordOpened(url: folder)

        #expect(store.records.count == 1)
        #expect(record.path == folder.standardizedFileURL.path)
        #expect(record.displayName == folder.lastPathComponent)
        #expect(UUID(uuidString: record.id.uuidString) != nil)
    }

    @Test func reopeningTheSameFolderRetainsItsStableUUID() throws {
        let store = RecentWorkspaceStore(defaults: makeIsolatedDefaults())
        let folder = try makeTemporaryDirectory()

        let first = store.recordOpened(url: folder)
        let second = store.recordOpened(url: folder)

        #expect(first.id == second.id)
        #expect(store.records.count == 1, "Reopening the same folder must update, not duplicate, the entry")
    }

    @Test func recordingADifferentFolderCreatesADifferentUUID() throws {
        let store = RecentWorkspaceStore(defaults: makeIsolatedDefaults())
        let first = store.recordOpened(url: try makeTemporaryDirectory())
        let second = store.recordOpened(url: try makeTemporaryDirectory())

        #expect(first.id != second.id)
        #expect(store.records.count == 2)
    }

    @Test func removingARecordDeletesOnlyThatEntry() throws {
        let store = RecentWorkspaceStore(defaults: makeIsolatedDefaults())
        let keep = store.recordOpened(url: try makeTemporaryDirectory())
        let removeMe = store.recordOpened(url: try makeTemporaryDirectory())

        store.remove(id: removeMe.id)

        #expect(store.records.count == 1)
        #expect(store.records.first?.id == keep.id)
    }

    @Test func clearingAllRecordsRemovesAndPersistsTheRecentList() throws {
        let defaults = makeIsolatedDefaults()
        let store = RecentWorkspaceStore(defaults: defaults)
        _ = store.recordOpened(url: try makeTemporaryDirectory())
        _ = store.recordOpened(url: try makeTemporaryDirectory())

        store.clearAll()

        #expect(store.records.isEmpty)
        #expect(RecentWorkspaceStore(defaults: defaults).records.isEmpty)
    }

    @Test func recordsPersistAcrossStoreInstancesSharingTheSameDefaults() throws {
        let defaults = makeIsolatedDefaults()
        let folder = try makeTemporaryDirectory()

        let firstStore = RecentWorkspaceStore(defaults: defaults)
        let created = firstStore.recordOpened(url: folder)

        let secondStore = RecentWorkspaceStore(defaults: defaults)
        #expect(secondStore.records.count == 1)
        #expect(secondStore.records.first?.id == created.id)
    }

    @Test func recentWorkspaceHistoryIsFixedAtTenEntries() {
        let store = RecentWorkspaceStore(defaults: makeIsolatedDefaults())
        let urls = (0..<15).map { index in
            URL(fileURLWithPath: "/tmp/SimpleCodeRecent-\(index)", isDirectory: true)
        }

        store.replaceForUITesting(urls: urls)

        #expect(store.records.count == 10)
        #expect(store.records.map(\.displayName) == urls.prefix(10).map(\.lastPathComponent))
    }

    @Test func oversizedPersistedHistoryIsNormalizedAtLaunch() throws {
        let defaults = makeIsolatedDefaults()
        let key = "recentWorkspaces.v1"
        let records = (0..<15).map { index in
            WorkspaceRecord(
                displayName: "Workspace-\(index)",
                path: "/tmp/SimpleCodePersisted-\(index)",
                bookmarkData: nil
            )
        }
        defaults.set(try JSONEncoder().encode(records), forKey: key)

        let store = RecentWorkspaceStore(defaults: defaults, storageKey: key)

        #expect(store.records.count == 10)
        #expect(store.records.map(\.id) == records.prefix(10).map(\.id))
        let persisted = try #require(defaults.data(forKey: key))
        #expect(try JSONDecoder().decode([WorkspaceRecord].self, from: persisted).count == 10)
    }

    @Test func corruptedPersistedDataFallsBackToAnEmptyListRatherThanCrashing() {
        let defaults = makeIsolatedDefaults()
        defaults.set(Data([0x00, 0x01, 0x02, 0xFF]), forKey: "recentWorkspaces.v1")

        let store = RecentWorkspaceStore(defaults: defaults, storageKey: "recentWorkspaces.v1")

        #expect(store.records.isEmpty)
    }

    @Test func resolvingAnExistingFolderMarksItAvailable() throws {
        let store = RecentWorkspaceStore(defaults: makeIsolatedDefaults())
        let folder = try makeTemporaryDirectory()
        let record = store.recordOpened(url: folder)

        let resolved = store.resolvedURL(for: record.id)

        #expect(resolved != nil)
        #expect(store.records.first?.isUnavailable == false)
    }

    @Test func resolvingADeletedFolderMarksItUnavailableWithoutCrashing() throws {
        let store = RecentWorkspaceStore(defaults: makeIsolatedDefaults())
        let folder = try makeTemporaryDirectory()
        let record = store.recordOpened(url: folder)

        try FileManager.default.removeItem(at: folder)

        let resolved = store.resolvedURL(for: record.id)

        #expect(resolved == nil)
        #expect(store.records.first?.isUnavailable == true)
        #expect(store.records.count == 1, "An unresolvable record must be kept, not silently deleted")
    }

    @Test func partiallyCorruptedPersistedDataFallsBackToAnEmptyList() throws {
        let defaults = makeIsolatedDefaults()
        var data = try JSONEncoder().encode([
            WorkspaceRecord(displayName: "A", path: "/tmp/a", bookmarkData: nil)
        ])
        data.append(contentsOf: [0xFF, 0xFE])

        defaults.set(data, forKey: "recentWorkspaces.v1")

        let store = RecentWorkspaceStore(defaults: defaults, storageKey: "recentWorkspaces.v1")

        #expect(store.records.isEmpty)
    }
}

struct WorkspaceRecordCodableTests {
    @Test func encodingAndDecodingRoundTripsAllFields() throws {
        let original = WorkspaceRecord(
            id: UUID(),
            displayName: "MyProject",
            path: "/Users/example/MyProject",
            bookmarkData: Data([1, 2, 3]),
            lastOpenedDate: Date(timeIntervalSince1970: 1_700_000_000),
            isUnavailable: true
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkspaceRecord.self, from: data)

        #expect(decoded == original)
    }

    @Test func recentRowPresentationExposesTheSimpleNameInsteadOfThePath() {
        let record = WorkspaceRecord(
            displayName: "SimpleCode",
            path: "/Users/example/Private/Repositories/SimpleCode",
            bookmarkData: nil
        )

        let presentation = RecentWorkspacePresentation(record: record)

        #expect(presentation.name == "SimpleCode")
        #expect(presentation.name != record.path)
    }

    @Test func recentRowPresentationMapsAvailabilityState() {
        let available = WorkspaceRecord(
            displayName: "Available",
            path: "/tmp/available",
            bookmarkData: nil
        )
        let unavailable = WorkspaceRecord(
            displayName: "Unavailable",
            path: "/tmp/unavailable",
            bookmarkData: nil,
            isUnavailable: true
        )

        #expect(RecentWorkspacePresentation(record: available).availability == .available)
        #expect(RecentWorkspacePresentation(record: unavailable).availability == .unavailable)
    }
}
