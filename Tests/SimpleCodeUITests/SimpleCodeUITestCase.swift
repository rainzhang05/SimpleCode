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

    func terminateStaleAppInstances() {
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: testedAppBundleID) {
            running.terminate()
        }
        let deadline = Date().addingTimeInterval(3)
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
