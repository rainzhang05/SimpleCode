import AppKit
import Foundation
import Testing
@testable import SimpleCode

struct PerformanceAcceptanceTests {
    @Test func fiveThousandLineHighlightingFixtures() async throws {
        let fixtures: [(LanguageID, String)] = [
            (.swift, Self.swiftFixture(lines: 5_000)),
            (.c, Self.cFixture(lines: 5_000)),
            (.cpp, Self.cppFixture(lines: 5_000)),
            (.python, Self.pythonFixture(lines: 5_000)),
            (.javascript, Self.javascriptFixture(lines: 5_000)),
        ]

        for (language, text) in fixtures {
            let highlighter = try #require(HighlightProviderFactory.makeHighlighter(for: language))
            let start = Date()
            let batch = await highlighter.load(text: text, revision: 1)
            let elapsed = Date().timeIntervalSince(start)
            print("PERF highlight.\(language.rawValue)=\(elapsed)")
            #expect(batch.revision == 1)
            #expect(!batch.coveredRanges.isEmpty)
        }
    }

    @MainActor
    @Test func tenTabsRapidSwitchingAndParserCleanup() {
        let store = OpenDocumentsStore()
        let text = Self.swiftFixture(lines: 120)
        let startOpen = Date()
        for index in 0..<10 {
            store.openSample(text: text, displayName: "Tab\(index).swift")
        }
        let openElapsed = Date().timeIntervalSince(startOpen)

        let startSwitch = Date()
        for _ in 0..<20 {
            for session in store.sessions {
                store.activate(session)
            }
        }
        let switchElapsed = Date().timeIntervalSince(startSwitch)

        let closing = try! #require(store.activeSession)
        #expect(closing.highlighter != nil)
        _ = store.close(sessionID: closing.id, force: true)
        #expect(store.recentlyClosed.isEmpty)

        print("PERF tabs.open10=\(openElapsed)")
        print("PERF tabs.switch200=\(switchElapsed)")
    }

    @MainActor
    @Test func findAndReplaceSeveralThousandResults() async {
        let controller = FindReplaceController()
        let text = String(repeating: "foo bar foo baz\n", count: 3_000)
        controller.bind(text: text, selection: NSRange(location: 0, length: 0))
        controller.searchText = "foo"

        let startFind = Date()
        controller.showFind()
        try? await Task.sleep(for: .milliseconds(220))
        let findElapsed = Date().timeIntervalSince(startFind)
        #expect(controller.matches.count == 6_000)

        controller.replaceText = "qux"
        let startReplace = Date()
        let replaced = controller.replaceAll(in: text)
        let replaceElapsed = Date().timeIntervalSince(startReplace)
        #expect(replaced?.contains("foo") == false)

        print("PERF find.6000=\(findElapsed)")
        print("PERF replaceAll.6000=\(replaceElapsed)")
    }

    @MainActor
    @Test func visualSettingTogglesAreBounded() {
        let textView = CodeTextView()
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        textView.string = Self.swiftFixture(lines: 5_000)
        let overlay = EditorOverlayView()
        overlay.textView = textView

        let startWrap = Date()
        textView.configureWordWrap(enabled: true, in: scrollView)
        textView.configureWordWrap(enabled: false, in: scrollView)
        let wrapElapsed = Date().timeIntervalSince(startWrap)

        let startVisuals = Date()
        overlay.showWhitespace = true
        overlay.showTrailingWhitespace = true
        overlay.showLongLineGuide = true
        overlay.guideColumn = 120
        overlay.needsDisplay = true
        let visualElapsed = Date().timeIntervalSince(startVisuals)

        print("PERF wordWrap.toggle=\(wrapElapsed)")
        print("PERF visuals.configure=\(visualElapsed)")
        #expect(textView.string.utf16.count > 0)
    }

    private static func swiftFixture(lines: Int) -> String {
        (0..<lines).map { "func f\($0)() -> Int { return \($0) }" }.joined(separator: "\n")
    }

    private static func cFixture(lines: Int) -> String {
        (0..<lines).map { "int f\($0)(void) { return \($0); }" }.joined(separator: "\n")
    }

    private static func cppFixture(lines: Int) -> String {
        (0..<lines).map { "namespace n\($0) { template <typename T> class C { T value; }; }" }.joined(separator: "\n")
    }

    private static func pythonFixture(lines: Int) -> String {
        (0..<lines).map { "def f_\($0)(value):\n    return value + \($0)" }.joined(separator: "\n")
    }

    private static func javascriptFixture(lines: Int) -> String {
        (0..<lines).map { "const f\($0) = (value) => value + \($0);" }.joined(separator: "\n")
    }
}
