import XCTest

@MainActor
final class SimpleCodeRunUITests: SimpleCodeUITestCase {
    func testRunButtonExists() throws {
        _ = try openRunFixture()
        XCTAssertTrue(app.buttons["workspace.runButton"].exists)
        XCTAssertTrue(app.buttons["workspace.runConfigButton"].exists)
    }

    func testRunConfigPopoverOpens() throws {
        _ = try openRunFixture()
        let configButton = app.buttons["workspace.runConfigButton"]
        XCTAssertTrue(configButton.waitForExistence(timeout: 8))
        configButton.click()
        XCTAssertTrue(app.textFields["run.popover.commandField"].waitForExistence(timeout: 5))
    }

    func testCommandCanBeEntered() throws {
        _ = try openRunFixture()
        app.buttons["workspace.runConfigButton"].click()
        let field = app.textFields["run.popover.commandField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText("printf 'entered'\n")
        XCTAssertTrue(field.value as? String != nil)
    }

    func testSuggestionAppears() throws {
        _ = try openRunFixture()
        app.buttons["workspace.runConfigButton"].click()
        XCTAssertTrue(app.otherElements["run.popover.suggestion"].waitForExistence(timeout: 8))
    }

    func testUseSuggestionFillsCommand() throws {
        _ = try openRunFixture()
        app.buttons["workspace.runConfigButton"].click()
        let useButton = app.buttons["run.popover.useSuggestion"]
        XCTAssertTrue(useButton.waitForExistence(timeout: 8))
        useButton.click()
        let field = app.textFields["run.popover.commandField"]
        XCTAssertTrue((field.value as? String ?? "").contains("swift run"))
    }

    func testEmptyCommandCannotRun() throws {
        let fixture = try makeTempDirectory()
        launchApp(extraArguments: ["-UITestFixtureRunWorkspace", fixture.path])
        waitForWorkspace()
        app.buttons["workspace.runConfigButton"].click()
        let field = app.textFields["run.popover.commandField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(" ")
        app.buttons["Done"].click()
        let runButton = app.buttons["workspace.runButton"]
        waitForEnabled(runButton)
        XCTAssertFalse(runButton.isEnabled)
    }

    func testUntrustedRunPresentsTrustSheet() throws {
        let fixture = try makeTempDirectory()
        openWorkspace(at: fixture, extraArguments: ["-UITestRunCommand", "printf test\n"])
        let runButton = app.buttons["workspace.runButton"]
        waitForEnabled(runButton)
        runButton.click()
        XCTAssertTrue(app.buttons["trust.sheet.runOnce"].waitForExistence(timeout: 8))
    }

    func testTrustCancelSubmitsNothing() throws {
        let fixture = try makeTempDirectory()
        openWorkspace(at: fixture, extraArguments: ["-UITestRunCommand", "printf test\n"])
        waitForEnabled(app.buttons["workspace.runButton"])
        app.buttons["workspace.runButton"].click()
        XCTAssertTrue(app.buttons["trust.sheet.cancel"].waitForExistence(timeout: 8))
        app.buttons["trust.sheet.cancel"].click()
        XCTAssertFalse(app.buttons["trust.sheet.runOnce"].exists)
        XCTAssertEqual(app.buttons["workspace.stopButton"].exists, false)
    }

    func testRunOnceSubmitsOnce() throws {
        let fixture = try makeTempDirectory()
        openWorkspace(at: fixture, extraArguments: ["-UITestRunCommand", "printf test\n"])
        waitForEnabled(app.buttons["workspace.runButton"])
        app.buttons["workspace.runButton"].click()
        let runOnce = app.buttons["trust.sheet.runOnce"]
        XCTAssertTrue(runOnce.waitForExistence(timeout: 8))
        runOnce.click()
        XCTAssertTrue(app.buttons["workspace.stopButton"].waitForExistence(timeout: 5))
    }

    func testTrustAndRunSubmitsOnce() throws {
        let fixture = try makeTempDirectory()
        openWorkspace(at: fixture, extraArguments: ["-UITestRunCommand", "printf trusted\n"])
        waitForEnabled(app.buttons["workspace.runButton"])
        app.buttons["workspace.runButton"].click()
        let trustAndRun = app.buttons["trust.sheet.trustAndRun"]
        XCTAssertTrue(trustAndRun.waitForExistence(timeout: 8))
        trustAndRun.click()
        XCTAssertTrue(app.buttons["workspace.stopButton"].waitForExistence(timeout: 5))
    }

    func testPersistedTrustSurvivesRelaunch() throws {
        useIsolatedDefaults()
        let fixture = try makeTempDirectory()
        openWorkspace(at: fixture, extraArguments: [
            "-UITestRunCommand", "printf trusted\n",
            "-UITestTrustDecision", "trusted"
        ])
        relaunchApp(extraArguments: ["-UITestOpenFolder", fixture.path, "-UITestRunCommand", "printf again\n"])
        waitForWorkspace()
        waitForEnabled(app.buttons["workspace.runButton"])
        app.buttons["workspace.runButton"].click()
        XCTAssertFalse(app.buttons["trust.sheet.runOnce"].waitForExistence(timeout: 2))
    }

    func testRevokeTrustRestoresGate() throws {
        let fixture = try makeTempDirectory()
        openWorkspace(at: fixture, extraArguments: ["-UITestTrustDecision", "trusted"])
        app.buttons["workspace.runConfigButton"].click()
        let revoke = app.buttons["run.popover.markUntrusted"]
        XCTAssertTrue(revoke.waitForExistence(timeout: 5))
        revoke.click()
        app.buttons["Done"].click()
        app.buttons["workspace.runConfigButton"].click()
        app.textFields["run.popover.commandField"].click()
        app.textFields["run.popover.commandField"].typeText("printf x\n")
        app.buttons["Done"].click()
        waitForEnabled(app.buttons["workspace.runButton"])
        app.buttons["workspace.runButton"].click()
        XCTAssertTrue(app.buttons["trust.sheet.runOnce"].waitForExistence(timeout: 8))
    }

    func testTerminalRevealPreferenceWorks() throws {
        _ = try openRunFixture(extraArguments: ["-UITestRunCommand", "printf reveal\n", "-UITestTrustDecision", "trusted"])
        app.buttons["workspace.runConfigButton"].click()
        let reveal = app.toggles["run.popover.revealTerminal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 5))
        if !(reveal.value as? String == "1") { reveal.click() }
        app.buttons["Done"].click()
        app.buttons["workspace.terminalToggle"].click()
        waitForEnabled(app.buttons["workspace.runButton"])
        app.buttons["workspace.runButton"].click()
        XCTAssertTrue(app.buttons["terminal.restartButton"].waitForExistence(timeout: 8))
    }

    func testClearBeforeRunPreferenceExists() throws {
        _ = try openRunFixture()
        app.buttons["workspace.runConfigButton"].click()
        XCTAssertTrue(app.toggles["run.popover.clearTerminal"].waitForExistence(timeout: 5))
    }

    func testStopButtonAppearsForRunningCommand() throws {
        let fixture = try makeTempDirectory()
        openWorkspace(at: fixture, extraArguments: [
            "-UITestRunCommand", "sleep 30\n",
            "-UITestTrustDecision", "trusted"
        ])
        waitForEnabled(app.buttons["workspace.runButton"])
        app.buttons["workspace.runButton"].click()
        XCTAssertTrue(app.buttons["workspace.stopButton"].waitForExistence(timeout: 8))
        app.buttons["workspace.stopButton"].click()
    }

    func testRestartConfirmationAppears() throws {
        _ = try openRunFixture(extraArguments: ["-UITestTrustDecision", "trusted"])
        app.buttons["workspace.terminalToggle"].click()
        app.menuBars.menuBarItems["Run"].click()
        app.menuItems["Restart Terminal…"].click()
        XCTAssertTrue(app.dialogs["Restart Terminal?"].waitForExistence(timeout: 5)
            || app.staticTexts["Restart Terminal?"].waitForExistence(timeout: 5))
    }
}
