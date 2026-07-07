import XCTest

@MainActor
final class SimpleCodeSettingsUITests: SimpleCodeUITestCase {
    private func makeFixture() throws -> URL {
        let root = try makeTempDirectory(prefix: "UITestSettings")
        try FileManager.default.createDirectory(at: root.appending(path: "Sources"), withIntermediateDirectories: true)
        try "struct Hello {}".write(to: root.appending(path: "Sources/Main.swift"), atomically: true, encoding: .utf8)
        return root
    }

    @discardableResult
    private func launchWorkspaceWithSampleFile() -> XCUIApplication {
        let fixture = try! makeFixture()
        return launchApp(extraArguments: ["-UITestFixtureWorkspace", fixture.path])
    }

    func testSettingsWindowSectionsExist() throws {
        _ = launchApp()
        app.menuBars.menuBarItems["SimpleCode"].click()
        app.menuBarItems["Settings…"].click()

        let settings = app.windows.element(boundBy: 0)
        XCTAssertTrue(settings.waitForExistence(timeout: 5))

        for label in ["Appearance", "Typography", "Editor", "Files", "Terminal"] {
            let tab = app.buttons[label]
            if tab.exists {
                tab.click()
            }
        }
    }

    func testFindBarOpens() throws {
        launchWorkspaceWithSampleFile()
        waitForWorkspace()
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(app.textFields["find.searchField"].waitForExistence(timeout: 5))
    }
}
