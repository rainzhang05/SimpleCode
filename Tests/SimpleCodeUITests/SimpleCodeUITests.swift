import XCTest

@MainActor
final class SimpleCodeUITests: SimpleCodeUITestCase {
    func testWelcomeScreenOnLaunch() throws {
        launchApp()
        waitForWelcome()
    }

    func testWelcomePrimaryActionsExist() throws {
        launchApp()
        waitForWelcome()
        XCTAssertTrue(app.buttons["welcome.Create a New Folder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["welcome.Open an Existing Folder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["welcome.Clone a Git Repository"].waitForExistence(timeout: 5))
    }

    func testCloneSheetIsFunctional() throws {
        openCloneSheet()
        let sheet = cloneSheetRoot()
        XCTAssertTrue(sheet.textFields["clone.sheet.urlField"].waitForExistence(timeout: 5))
    }

    func testLaunchArgumentOpensWorkspace() throws {
        let fixture = try makeTempDirectory()
        openWorkspace(at: fixture)
        XCTAssertTrue(app.staticTexts[fixture.lastPathComponent].waitForExistence(timeout: 5))
    }

    func testTerminalHideAndReveal() throws {
        let fixture = try makeTempDirectory()
        openWorkspace(at: fixture)
        let toggle = app.buttons["workspace.terminalToggle"]
        toggle.click()
        toggle.click()
        XCTAssertTrue(toggle.exists)
    }

    func testCloseWorkspaceReturnsToWelcome() throws {
        let fixture = try makeTempDirectory()
        openWorkspace(at: fixture)
        app.typeKey("w", modifierFlags: [.command, .shift])
        waitForWelcome()
    }

    func testRelaunchWithIsolatedDefaultsDoesNotCrash() throws {
        useIsolatedDefaults()
        let fixture = try makeTempDirectory()
        openWorkspace(at: fixture)
        relaunchApp()
        waitForWelcome()
    }

    func testDarkModeLaunch() throws {
        app.launchEnvironment["AppleInterfaceStyle"] = "Dark"
        launchApp()
        waitForWelcome()
    }
}
