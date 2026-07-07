import XCTest

@MainActor
final class SimpleCodeEditorUITests: SimpleCodeUITestCase {
    private func makeFixture() throws -> URL {
        let root = try makeTempDirectory(prefix: "UITest")
        try FileManager.default.createDirectory(at: root.appending(path: "Sources"), withIntermediateDirectories: true)
        try "struct Hello {}".write(to: root.appending(path: "Sources/Main.swift"), atomically: true, encoding: .utf8)
        try "let other = 1".write(to: root.appending(path: "Sources/Other.swift"), atomically: true, encoding: .utf8)
        return root
    }

    func testFileTreeAndOpenTabs() throws {
        let fixture = try makeFixture()
        launchApp(extraArguments: ["-UITestFixtureWorkspace", fixture.path])
        waitForWorkspace()

        let disclosure = app.descendants(matching: .any)["fileTree.disclosure.Sources"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 8))
        disclosure.click()

        let mainRow = app.descendants(matching: .any)["fileTree.row.Sources/Main.swift"]
        XCTAssertTrue(mainRow.waitForExistence(timeout: 8))
        mainRow.click()
        XCTAssertTrue(app.buttons["editor.tab.Main.swift"].waitForExistence(timeout: 8))

        let otherRow = app.descendants(matching: .any)["fileTree.row.Sources/Other.swift"]
        XCTAssertTrue(otherRow.waitForExistence(timeout: 8))
        otherRow.click()
        XCTAssertTrue(app.buttons["editor.tab.Other.swift"].waitForExistence(timeout: 8))
    }
}
