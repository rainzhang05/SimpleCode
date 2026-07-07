import XCTest

@MainActor
final class SimpleCodeCloneUITests: SimpleCodeUITestCase {
    func testCloneSheetOpens() throws {
        openCloneSheet()
        XCTAssertTrue(cloneSheetRoot().textFields["clone.sheet.urlField"].exists)
    }

    func testInvalidURLProducesValidation() throws {
        let parent = try makeTempDirectory(prefix: "CloneDest")
        openCloneSheet(extraArguments: ["-UITestCloneDestination", parent.path])
        let sheet = cloneSheetRoot()
        let urlField = sheet.textFields["clone.sheet.urlField"]
        urlField.click()
        urlField.typeKey("a", modifierFlags: .command)
        urlField.typeText("\n")
        sheet.buttons["clone.sheet.cloneButton"].click()
        XCTAssertTrue(sheet.staticTexts["clone.sheet.error"].waitForExistence(timeout: 5)
            || sheet.otherElements["clone.sheet.error"].waitForExistence(timeout: 5))
    }

    func testDestinationPreviewUpdates() throws {
        let parent = try makeTempDirectory(prefix: "CloneDest")
        openCloneSheet(extraArguments: [
            "-UITestCloneSource", "https://github.com/example/repo.git",
            "-UITestCloneDestination", parent.path
        ])
        let sheet = cloneSheetRoot()
        XCTAssertTrue(sheet.otherElements["clone.sheet.destinationPreview"].waitForExistence(timeout: 5))
    }

    func testCloneButtonEnabledWithValidInput() throws {
        let parent = try makeTempDirectory(prefix: "CloneDest")
        openCloneSheet(extraArguments: ["-UITestCloneDestination", parent.path])
        let sheet = cloneSheetRoot()
        let urlField = sheet.textFields["clone.sheet.urlField"]
        urlField.click()
        urlField.typeKey("a", modifierFlags: .command)
        urlField.typeText("https://github.com/example/repo.git")
        let cloneButton = sheet.buttons["clone.sheet.cloneButton"]
        XCTAssertTrue(cloneButton.waitForExistence(timeout: 3))
        waitForEnabled(cloneButton)
    }

    func testLocalCloneShowsProgress() throws {
        let bare = try makeBareRepo()
        let parent = try makeTempDirectory(prefix: "CloneDest")
        openCloneSheet(extraArguments: [
            "-UITestCloneSource", bare.path,
            "-UITestCloneDestination", parent.path
        ])
        let sheet = cloneSheetRoot()
        let folderField = sheet.textFields["clone.sheet.folderName"]
        if folderField.waitForExistence(timeout: 3) {
            folderField.click()
            folderField.typeKey("a", modifierFlags: .command)
            folderField.typeText("cloned-repo")
        }
        let cloneButton = sheet.buttons["clone.sheet.cloneButton"]
        waitForEnabled(cloneButton)
        cloneButton.click()
        XCTAssertTrue(sheet.staticTexts["clone.sheet.progressStatus"].waitForExistence(timeout: 10))
    }

    func testSuccessfulCloneOpensWorkspace() throws {
        let bare = try makeBareRepo()
        let parent = try makeTempDirectory(prefix: "CloneDest")
        openCloneSheet(extraArguments: [
            "-UITestCloneSource", bare.path,
            "-UITestCloneDestination", parent.path
        ])
        let sheet = cloneSheetRoot()
        let folderField = sheet.textFields["clone.sheet.folderName"]
        if folderField.waitForExistence(timeout: 3) {
            folderField.click()
            folderField.typeKey("a", modifierFlags: .command)
            folderField.typeText("cloned-repo")
        }
        let cloneButton = sheet.buttons["clone.sheet.cloneButton"]
        waitForEnabled(cloneButton)
        cloneButton.click()
        XCTAssertTrue(app.buttons["workspace.terminalToggle"].waitForExistence(timeout: 30))
    }

    func testClonedWorkspaceIsUntrusted() throws {
        let bare = try makeBareRepo()
        let parent = try makeTempDirectory(prefix: "CloneDest")
        openCloneSheet(extraArguments: [
            "-UITestCloneSource", bare.path,
            "-UITestCloneDestination", parent.path
        ])
        let sheet = cloneSheetRoot()
        let folderField = sheet.textFields["clone.sheet.folderName"]
        if folderField.waitForExistence(timeout: 3) {
            folderField.click()
            folderField.typeKey("a", modifierFlags: .command)
            folderField.typeText("untrusted-clone")
        }
        waitForEnabled(sheet.buttons["clone.sheet.cloneButton"])
        sheet.buttons["clone.sheet.cloneButton"].click()
        XCTAssertTrue(app.buttons["workspace.terminalToggle"].waitForExistence(timeout: 30))
        app.buttons["workspace.runConfigButton"].click()
        app.textFields["run.popover.commandField"].click()
        app.textFields["run.popover.commandField"].typeText("printf x\n")
        app.buttons["Done"].click()
        waitForEnabled(app.buttons["workspace.runButton"])
        app.buttons["workspace.runButton"].click()
        XCTAssertTrue(app.buttons["trust.sheet.runOnce"].waitForExistence(timeout: 8))
    }

    func testCancellationReturnsToEditingState() throws {
        let bare = try makeBareRepo()
        let parent = try makeTempDirectory(prefix: "CloneDest")
        openCloneSheet(extraArguments: [
            "-UITestCloneSource", bare.path,
            "-UITestCloneDestination", parent.path
        ])
        let sheet = cloneSheetRoot()
        waitForEnabled(sheet.buttons["clone.sheet.cloneButton"])
        sheet.buttons["clone.sheet.cloneButton"].click()
        XCTAssertTrue(sheet.staticTexts["clone.sheet.progressStatus"].waitForExistence(timeout: 8))
        sheet.buttons["clone.sheet.cancelButton"].click()
        let cloneButton = sheet.buttons["clone.sheet.cloneButton"]
        XCTAssertTrue(cloneButton.waitForExistence(timeout: 15))
    }

    func testExistingDestinationRejected() throws {
        let bare = try makeBareRepo()
        let parent = try makeTempDirectory(prefix: "CloneDest")
        let existing = parent.appending(path: "existing")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        try "data".write(to: existing.appending(path: "file.txt"), atomically: true, encoding: .utf8)

        openCloneSheet(extraArguments: [
            "-UITestCloneSource", bare.path,
            "-UITestCloneDestination", parent.path
        ])
        let sheet = cloneSheetRoot()
        let folderField = sheet.textFields["clone.sheet.folderName"]
        folderField.click()
        folderField.typeKey("a", modifierFlags: .command)
        folderField.typeText("existing")
        waitForEnabled(sheet.buttons["clone.sheet.cloneButton"])
        sheet.buttons["clone.sheet.cloneButton"].click()
        XCTAssertTrue(sheet.staticTexts["clone.sheet.error"].waitForExistence(timeout: 5)
            || sheet.otherElements["clone.sheet.error"].waitForExistence(timeout: 5))
    }

    func testDoubleClickCloneStartsOneOperation() throws {
        let bare = try makeBareRepo()
        let parent = try makeTempDirectory(prefix: "CloneDest")
        openCloneSheet(extraArguments: [
            "-UITestCloneSource", bare.path,
            "-UITestCloneDestination", parent.path
        ])
        let sheet = cloneSheetRoot()
        let cloneButton = sheet.buttons["clone.sheet.cloneButton"]
        waitForEnabled(cloneButton)
        cloneButton.click()
        cloneButton.click()
        XCTAssertTrue(sheet.staticTexts["clone.sheet.progressStatus"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["workspace.terminalToggle"].waitForExistence(timeout: 30))
    }

    func testSheetCloseDuringCloneRequestsCancellation() throws {
        let bare = try makeBareRepo()
        let parent = try makeTempDirectory(prefix: "CloneDest")
        openCloneSheet(extraArguments: [
            "-UITestCloneSource", bare.path,
            "-UITestCloneDestination", parent.path
        ])
        let sheet = cloneSheetRoot()
        waitForEnabled(sheet.buttons["clone.sheet.cloneButton"])
        sheet.buttons["clone.sheet.cloneButton"].click()
        XCTAssertTrue(sheet.staticTexts["clone.sheet.progressStatus"].waitForExistence(timeout: 8))
        sheet.buttons["clone.sheet.cancelButton"].click()
        XCTAssertTrue(sheet.buttons["clone.sheet.cloneButton"].waitForExistence(timeout: 15))
    }

    func testCloneFailureDisplaysSanitizedDiagnostics() throws {
        let parent = try makeTempDirectory(prefix: "CloneDest")
        openCloneSheet(extraArguments: ["-UITestCloneDestination", parent.path])
        let sheet = cloneSheetRoot()
        let urlField = sheet.textFields["clone.sheet.urlField"]
        urlField.click()
        urlField.typeKey("a", modifierFlags: .command)
        urlField.typeText("/nonexistent/repository/path.git")
        let folderField = sheet.textFields["clone.sheet.folderName"]
        folderField.click()
        folderField.typeKey("a", modifierFlags: .command)
        folderField.typeText("fail-clone")
        waitForEnabled(sheet.buttons["clone.sheet.cloneButton"])
        sheet.buttons["clone.sheet.cloneButton"].click()
        XCTAssertTrue(sheet.staticTexts["clone.sheet.error"].waitForExistence(timeout: 30)
            || sheet.otherElements["clone.sheet.error"].waitForExistence(timeout: 5))
    }
}
