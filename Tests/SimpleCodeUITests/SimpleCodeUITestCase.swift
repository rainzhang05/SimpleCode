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
        [core]
            repositoryformatversion = 0
            filemode = true
            bare = true
            logallrefupdates = false
        """.write(to: repo.appending(path: "config"), atomically: true, encoding: .utf8)
        try "Unnamed repository; edit this file to name it for gitweb.\n"
            .write(to: repo.appending(path: "description"), atomically: true, encoding: .utf8)
        try "# exclude patterns\n".write(to: repo.appending(path: "info/exclude"), atomically: true, encoding: .utf8)
    }

    @MainActor
    func waitForWelcome(timeout: TimeInterval = 30) {
        let clone = app.buttons["welcome.Clone a Git Repository"]
        if clone.waitForExistence(timeout: timeout) { return }
        XCTAssertTrue(
            app.staticTexts["welcome.title"].waitForExistence(timeout: 5)
            || app.staticTexts["SimpleCode"].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func waitForWorkspace(timeout: TimeInterval = 20) {
        XCTAssertTrue(app.buttons["workspace.terminalToggle"].waitForExistence(timeout: timeout))
    }

    @MainActor
    func openWorkspace(at url: URL, extraArguments: [String] = []) {
        launchApp(extraArguments: ["-UITestOpenFolder", url.path] + extraArguments)
        waitForWorkspace()
    }

    @MainActor
    func openRunFixture(extraArguments: [String] = []) throws -> URL {
        let fixture = try makeRunFixture()
        launchApp(extraArguments: ["-UITestFixtureRunWorkspace", fixture.path] + extraArguments)
        waitForWorkspace()
        return fixture
    }

    @MainActor
    func cloneSheetRoot() -> XCUIElement {
        if app.sheets.firstMatch.waitForExistence(timeout: 5) {
            return app.sheets.firstMatch
        }
        return app.otherElements["clone.sheet"]
    }

    @MainActor
    func openCloneSheet(extraArguments: [String] = []) {
        launchApp(extraArguments: extraArguments)
        waitForWelcome()
        let cloneCard = app.buttons["welcome.Clone a Git Repository"]
        XCTAssertTrue(cloneCard.waitForExistence(timeout: 8))
        cloneCard.click()
        let sheet = cloneSheetRoot()
        XCTAssertTrue(sheet.staticTexts["Clone a Git Repository"].waitForExistence(timeout: 8))
    }

    @MainActor
    func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval = 20) {
        let predicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "Element not enabled within \(timeout)s")
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
