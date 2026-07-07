import Foundation
import Testing
@testable import SimpleCode

@Suite(.serialized)
@MainActor
struct TabIndependenceTests {
    @Test func tenTabsHaveIndependentState() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var files: [URL] = []
        for index in 0..<10 {
            let file = dir.appendingPathComponent("Tab\(index).swift")
            try "let v\(index) = \(index)".write(to: file, atomically: true, encoding: .utf8)
            files.append(file)
        }

        let store = OpenDocumentsStore()
        for file in files {
            await store.open(url: file)
        }
        #expect(store.sessions.count == 10)

        let storages = store.sessions.map(\.textStorage)
        let uniqueStorageIDs = Set(storages.map { ObjectIdentifier($0) })
        #expect(uniqueStorageIDs.count == 10)

        for (index, session) in store.sessions.enumerated() where index % 2 == 0 {
            session.textStorage.mutableString.setString("mutated \(index)")
            session.markDirty()
        }

        let dirtyFlags = store.sessions.map(\.isDirty)
        #expect(dirtyFlags == [true, false, true, false, true, false, true, false, true, false])

        store.activate(store.sessions[3])
        store.sessions[3].textStorage.mutableString.setString("tab3 changed")
        store.sessions[3].markDirty()
        #expect(store.sessions[0].textStorage.string.hasPrefix("mutated"))
        #expect(store.sessions[1].textStorage.string.hasPrefix("let v1"))
        #expect(store.sessions[3].textStorage.string == "tab3 changed")
    }
}
