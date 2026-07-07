import XCTest

class SimpleCodeUITestCase: XCTestCase {
    var app: XCUIApplication!
    var defaultsSuite: String?
    var ownedPaths: [URL] = []
    private let testedAppBundleID = "com.simplecode.app"

    override func setUpWithError() throws {
        continueAfterFailure = false
        terminateStaleAppInstances()
        useIsolatedDefaults()
        app = MainActor.assumeIsolated { XCUIApplication() }
    }

    override func tearDownWithError() throws {
        let launchedApp = app
        MainActor.assumeIsolated {
            launchedApp?.terminate()
        }
        for path in ownedPaths {
            try? FileManager.default.removeItem(at: path)
        }
        ownedPaths.removeAll()
        defaultsSuite = nil
    }

    @discardableResult
    @MainActor
    func launchApp(extraArguments: [String] = [], activate: Bool = true) -> XCUIApplication {
        app.launchArguments = launchArguments(extraArguments: extraArguments)
        app.launch()
        if activate { app.activate() }
        return app
    }

    func useIsolatedDefaults() {
        defaultsSuite = "com.simplecode.uitest.\(UUID().uuidString)"
        if let defaultsSuite, let defaults = UserDefaults(suiteName: defaultsSuite) {
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
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
    func makeRunFixture() throws -> URL {
        let fixture = try makeTempDirectory(prefix: "SimpleCodeRunFixture")
        try "// swift tools\n".write(
            to: fixture.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        return fixture
    }

    @discardableResult
    func makeBareRepo() throws -> URL {
        if let bundled = bundledBareRepoURL() {
            let base = try makeTempDirectory(prefix: "SimpleCodeBare")
            let repo = base.appending(path: "repo.git")
            try FileManager.default.copyItem(at: bundled, to: repo)
            return repo
        }
        let base = try makeTempDirectory(prefix: "SimpleCodeBare")
        let repo = base.appending(path: "repo.git")
        try createMinimalBareRepository(at: repo)
        return repo
    }

    private func bundledBareRepoURL() -> URL? {
        let bundle = Bundle(for: SimpleCodeUITestCase.self)
        if let url = bundle.url(
            forResource: "sample",
            withExtension: "git",
            subdirectory: "Fixtures"
        ) {
            return url
        }

        let directURL = bundle.resourceURL?
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("sample.git", isDirectory: true)
        if let directURL, FileManager.default.fileExists(atPath: directURL.path) {
            return directURL
        }
        return nil
    }

    private func createMinimalBareRepository(at repo: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: repo.appending(path: "objects/info"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: repo.appending(path: "objects/pack"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: repo.appending(path: "refs/heads"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: repo.appending(path: "refs/tags"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: repo.appending(path: "hooks"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: repo.appending(path: "info"), withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(to: repo.appending(path: "HEAD"), atomically: true, encoding: .utf8)
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
