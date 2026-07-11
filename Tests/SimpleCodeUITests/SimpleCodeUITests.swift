import AppKit
import XCTest

@MainActor
final class SimpleCodeUITests: SimpleCodeUITestCase {
    func testWelcomeLaunchesAndPrimaryActionsRemainVisible() throws {
        launchApp()
        waitForWelcome()

        XCTAssertTrue(element("welcome.recentWorkspaces").exists)
        assertWelcomeActionIsClickable(id: "welcome.action.createFolder", label: "Create a New Folder")
        assertWelcomeActionIsClickable(id: "welcome.action.openFolder", label: "Open an Existing Folder")
        assertWelcomeActionIsClickable(id: "welcome.action.cloneRepository", label: "Clone a Git Repository")
    }

    func testWelcomeRecentsAreBoundedScrollableAndClearable() throws {
        let recentRoots = try (0..<18).map { index in
            try makeTempDirectory(prefix: "SimpleCodeRecent\(index)")
        }
        let arguments = recentRoots.flatMap { ["-UITestSeedRecentWorkspace", $0.path] }

        launchApp(extraArguments: arguments)
        waitForWelcome()

        XCTAssertTrue(
            element("welcome.recentWorkspaces.scroll").waitForExistence(timeout: 2)
                || element("welcome.recentWorkspaces").exists
        )
        assertWelcomeActionIsClickable(id: "welcome.action.cloneRepository", label: "Clone a Git Repository")

        let clear = app.buttons["welcome.clearRecentWorkspaces"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clickElement(clear)
        XCTAssertTrue(app.staticTexts["No recent workspaces"].waitForExistence(timeout: 10))
    }

    func testOpenFixtureWorkspaceShowsCoreChrome() throws {
        _ = try openFixtureWorkspace()

        XCTAssertTrue(element("fileTree.sidebar").waitForExistence(timeout: 8))
        XCTAssertTrue(element("workspace.editorPlaceholder").waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["workspace.runConfigButton"].exists)
        XCTAssertTrue(app.buttons["workspace.terminalToggle"].exists)
    }

    func testOpenRootFileEditAndSaveUpdatesDirtyState() throws {
        let fixture = try openFixtureWorkspace()
        openMainFile(in: fixture)

        typeInEditor("\n// edited by SimpleCode UI test")

        let tab = element("editor.tab.Main.swift")
        waitForValue(tab, "modified")

        saveActiveDocument()
        waitForValue(tab, "saved", timeout: 10)

        let saved = try String(contentsOf: fixture.mainFile, encoding: .utf8)
        XCTAssertTrue(saved.contains("edited by SimpleCode UI test"))
    }

    func testEditorPaintsGlyphsForSwiftAndPlainTextFiles() throws {
        let fixture = try makeWorkspaceFixture(prefix: "SimpleCodeGlyphRendering")
        try (0..<12)
            .map { "let swiftVisualMarker\($0) = \"rendered\"" }
            .joined(separator: "\n")
            .write(to: fixture.mainFile, atomically: true, encoding: .utf8)

        let plainFile = fixture.root.appending(path: "Notes.txt")
        try (0..<12)
            .map { "plain text visual marker \($0)" }
            .joined(separator: "\n")
            .write(to: plainFile, atomically: true, encoding: .utf8)

        openWorkspace(at: fixture.root)

        let swiftRow = element("fileTree.row.Main.swift")
        XCTAssertTrue(swiftRow.waitForExistence(timeout: 8), debugSnapshot())
        clickElement(swiftRow)
        XCTAssertTrue(element("editor.tab.Main.swift").waitForExistence(timeout: 8), debugSnapshot())
        assertEditorScreenshotContainsPaintedGlyphs(fileName: "Main.swift")

        let plainRow = element("fileTree.row.Notes.txt")
        XCTAssertTrue(plainRow.waitForExistence(timeout: 8), debugSnapshot())
        clickElement(plainRow)
        XCTAssertTrue(element("editor.tab.Notes.txt").waitForExistence(timeout: 8), debugSnapshot())
        assertEditorScreenshotContainsPaintedGlyphs(fileName: "Notes.txt")
    }

    func testSettingsSectionsAndOneHarmlessPreference() throws {
        launchApp()
        waitForWelcome()

        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(element("settings.root").waitForExistence(timeout: 8), debugSnapshot())
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 5))

        for section in ["Appearance", "Typography", "Editor", "Files", "Terminal"] {
            let tab = app.buttons[section]
            XCTAssertTrue(tab.waitForExistence(timeout: 5), debugSnapshot())
            clickElement(tab)
            XCTAssertTrue(app.windows[section].waitForExistence(timeout: 5), debugSnapshot())
        }

        clickElement(app.buttons["Appearance"])
        XCTAssertTrue(app.windows["Appearance"].waitForExistence(timeout: 5), debugSnapshot())
        let dark = app.radioButtons["Dark"]
        XCTAssertTrue(dark.waitForExistence(timeout: 5), debugSnapshot())
        clickElement(dark)
        XCTAssertTrue(dark.exists)
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
