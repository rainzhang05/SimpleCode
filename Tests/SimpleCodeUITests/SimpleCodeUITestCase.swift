import AppKit
import XCTest

class SimpleCodeUITestCase: XCTestCase {
    struct WorkspaceFixture {
        let root: URL
        let mainFile: URL
    }

    var app: XCUIApplication!
    var defaultsSuite: String?
    var ownedPaths: [URL] = []

    private let testedAppBundleID = "com.simplecode.app"
    private let defaultTimeout: TimeInterval = 8
    private static let defaultsSuitePrefix = "com.simplecode.uitest."

    override class func tearDown() {
        removeUITestDefaultsDomains()
        super.tearDown()
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        Self.removeUITestDefaultsDomains()
        terminateStaleAppInstances()
        useIsolatedDefaults()
        app = MainActor.assumeIsolated { XCUIApplication() }
    }

    override func tearDownWithError() throws {
        let launchedApp = app
        MainActor.assumeIsolated {
            launchedApp?.terminate()
        }
        _ = waitForNoRunningApp(timeout: 2)
        terminateStaleAppInstances()
        removeOwnedPaths()
        removeIsolatedDefaults()
        defaultsSuite = nil
    }

    @discardableResult
    @MainActor
    func launchApp(extraArguments: [String] = [], activate: Bool = true) -> XCUIApplication {
        app.launchArguments = launchArguments(extraArguments: extraArguments)
        app.launchEnvironment = launchEnvironment()
        app.launch()
        if activate { app.activate() }
        XCTAssertTrue(
            waitForAnyRoot(timeout: defaultTimeout),
            "SimpleCode launched without exposing Welcome or Workspace UI.\n\(debugSnapshot())"
        )
        return app
    }

    func useIsolatedDefaults() {
        defaultsSuite = "com.simplecode.uitest.\(UUID().uuidString)"
        removeIsolatedDefaults()
    }

    @discardableResult
    func makeTempDirectory(prefix: String = "SimpleCodeUITest") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        ownedPaths.append(url)
        return url
    }

    @discardableResult
    func makeWorkspaceFixture(prefix: String = "SimpleCodeWorkspaceFixture") throws -> WorkspaceFixture {
        let root = try makeTempDirectory(prefix: prefix)
        let mainFile = root.appending(path: "Main.swift")
        try """
        import Foundation

        let greeting = "simplecode"
        print(greeting)
        """.write(to: mainFile, atomically: true, encoding: .utf8)
        try """
        # SimpleCode UI fixture
        """.write(to: root.appending(path: "README.md"), atomically: true, encoding: .utf8)
        return WorkspaceFixture(root: root, mainFile: mainFile)
    }

    @MainActor
    func waitForWelcome(timeout: TimeInterval = 8) {
        XCTAssertTrue(element("welcome.root").waitForExistence(timeout: timeout), debugSnapshot())
        XCTAssertTrue(welcomeAction(id: "welcome.action.createFolder", label: "Create a New Folder").exists)
        XCTAssertTrue(welcomeAction(id: "welcome.action.openFolder", label: "Open an Existing Folder").exists)
        XCTAssertTrue(welcomeAction(id: "welcome.action.cloneRepository", label: "Clone a Git Repository").exists)
    }

    @MainActor
    func waitForWorkspace(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            element("workspace.root").waitForExistence(timeout: timeout)
                || app.buttons["workspace.terminalToggle"].waitForExistence(timeout: 1),
            debugSnapshot()
        )
    }

    @MainActor
    func openWorkspace(at url: URL, extraArguments: [String] = []) {
        launchApp(extraArguments: ["-UITestFixtureWorkspace", url.path] + extraArguments)
        waitForWorkspace()
    }

    @discardableResult
    @MainActor
    func openFixtureWorkspace(extraArguments: [String] = []) throws -> WorkspaceFixture {
        let fixture = try makeWorkspaceFixture()
        openWorkspace(at: fixture.root, extraArguments: extraArguments)
        return fixture
    }

    @MainActor
    func openMainFile(in fixture: WorkspaceFixture) {
        let row = element("fileTree.row.Main.swift")
        XCTAssertTrue(row.waitForExistence(timeout: defaultTimeout), debugSnapshot())
        row.click()
        XCTAssertTrue(element("editor.tab.Main.swift").waitForExistence(timeout: defaultTimeout), debugSnapshot())
        XCTAssertTrue(element("editor.textView").waitForExistence(timeout: defaultTimeout), debugSnapshot())
    }

    @MainActor
    func openCloneSheet(extraArguments: [String] = []) {
        launchApp(extraArguments: extraArguments)
        waitForWelcome()
        clickWelcomeAction(id: "welcome.action.cloneRepository", label: "Clone a Git Repository")
        waitForModalSheet()
    }

    @MainActor
    func visibleSheet() -> XCUIElement {
        app.sheets.firstMatch
    }

    @MainActor
    func sheetElement(_ identifier: String) -> XCUIElement {
        visibleSheet().descendants(matching: .any)[identifier]
    }

    @MainActor
    func waitForModalSheet(timeout: TimeInterval = 8) {
        let window = app.windows.firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if window.exists && !window.isEnabled { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("Expected modal sheet presentation.\n\(debugSnapshot())")
    }

    @MainActor
    func welcomeAction(id: String, label: String) -> XCUIElement {
        let identified = element(id)
        if identified.exists { return identified }
        let button = app.buttons[label]
        if button.exists { return button }
        return app.staticTexts[label]
    }

    @MainActor
    func assertWelcomeActionIsClickable(id: String, label: String, file: StaticString = #filePath, line: UInt = #line) {
        let action = welcomeAction(id: id, label: label)
        XCTAssertTrue(action.waitForExistence(timeout: defaultTimeout), debugSnapshot(), file: file, line: line)
        XCTAssertFalse(action.frame.isEmpty, debugSnapshot(), file: file, line: line)
    }

    @MainActor
    func clickWelcomeAction(id: String, label: String) {
        let action = welcomeAction(id: id, label: label)
        XCTAssertTrue(action.waitForExistence(timeout: defaultTimeout), debugSnapshot())
        clickElement(action)
    }

    @MainActor
    func focusEditor(file: StaticString = #filePath, line: UInt = #line) {
        app.activate()
        let editor = element("editor.textView")
        XCTAssertTrue(editor.waitForExistence(timeout: defaultTimeout), debugSnapshot(), file: file, line: line)
        clickElement(editor)
        clickElement(editor)
    }

    @MainActor
    func typeInEditor(_ text: String) {
        focusEditor()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        pasteText(text)
    }

    @MainActor
    func typeInField(_ field: XCUIElement, text: String) {
        focusTextField(field)
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        pasteText(text)
    }

    @MainActor
    func pasteText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        app.typeKey("v", modifierFlags: .command)
    }

    @MainActor
    func clickElement(_ element: XCUIElement) {
        if element.isHittable {
            element.click()
            return
        }
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    @MainActor
    func focusTextField(_ field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: defaultTimeout), debugSnapshot())
        clickElement(field)
    }

    @MainActor
    func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval = 8) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.isEnabled { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("Element not enabled within \(timeout)s.\n\(debugSnapshot())")
    }

    @MainActor
    func waitForValue(_ element: XCUIElement, _ expectedValue: String, timeout: TimeInterval = 8) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let remaining = NSRunningApplication.runningApplications(withBundleIdentifier: testedAppBundleID)
            if remaining.isEmpty { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    @MainActor
    func relaunchApp(extraArguments: [String] = []) {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = launchArguments(extraArguments: extraArguments)
        app.launch()
        app.activate()
    }

    private func launchArguments(extraArguments: [String]) -> [String] {
        if let defaultsSuite {
            return ["-UITestUserDefaultsSuite", defaultsSuite] + extraArguments
        }
        return extraArguments
    }

}
