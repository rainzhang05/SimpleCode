import Foundation
import Testing
@testable import SimpleCode

@MainActor
struct FindReplaceControllerTests {
    @Test func findsPlainTextCaseInsensitive() async {
        let controller = FindReplaceController()
        controller.bind(text: "Hello hello HELLO", selection: NSRange(location: 0, length: 0))
        controller.searchText = "hello"
        controller.showFind()
        try? await Task.sleep(for: .milliseconds(200))
        #expect(controller.matches.count == 3)
    }

    @Test func matchCaseRequiresExactCase() async {
        let controller = FindReplaceController()
        controller.bind(text: "Hello hello", selection: NSRange(location: 0, length: 0))
        controller.searchText = "hello"
        controller.matchCase = true
        controller.showFind()
        try? await Task.sleep(for: .milliseconds(200))
        #expect(controller.matches.count == 1)
    }

    @Test func wholeWordSkipsPartialMatches() async {
        let controller = FindReplaceController()
        controller.bind(text: "cat category", selection: NSRange(location: 0, length: 0))
        controller.searchText = "cat"
        controller.wholeWord = true
        controller.showFind()
        try? await Task.sleep(for: .milliseconds(200))
        #expect(controller.matches.count == 1)
        #expect(controller.matches[0].range.location == 0)
    }

    @Test func selectionOnlyLimitsSearchRange() async {
        let controller = FindReplaceController()
        let text = "foo bar foo"
        controller.bind(text: text, selection: NSRange(location: 4, length: 3))
        controller.searchText = "foo"
        controller.selectionOnly = true
        controller.showFind()
        try? await Task.sleep(for: .milliseconds(200))
        #expect(controller.matches.isEmpty)
    }

    @Test func selectionChangeRetargetsMatchWithoutRescanning() async {
        let controller = FindReplaceController()
        controller.bind(text: "foo bar foo", selection: NSRange(location: 0, length: 0))
        controller.searchText = "foo"
        controller.showFind()
        try? await Task.sleep(for: .milliseconds(200))
        #expect(controller.matches.count == 2)
        let generation = controller.searchGeneration
        controller.updateSelection(NSRange(location: 8, length: 0))
        #expect(controller.searchGeneration == generation)
        #expect(controller.matches.count == 2)
        #expect(controller.currentMatchIndex == 1)
    }

    @Test func selectionOnlyResearchesOnSelectionChange() async {
        let controller = FindReplaceController()
        controller.bind(text: "foo bar foo", selection: NSRange(location: 0, length: 3))
        controller.searchText = "foo"
        controller.selectionOnly = true
        controller.showFind()
        try? await Task.sleep(for: .milliseconds(200))
        #expect(controller.matches.count == 1)
        #expect(controller.matches[0].range.location == 0)

        controller.updateSelection(NSRange(location: 8, length: 3))
        try? await Task.sleep(for: .milliseconds(200))
        #expect(controller.matches.count == 1)
        #expect(controller.matches[0].range.location == 8)
    }

    @Test func staleSearchResultsAreCancelled() async {
        let controller = FindReplaceController()
        controller.bind(text: "alpha beta gamma", selection: NSRange(location: 0, length: 0))
        controller.showFind()
        controller.searchText = "alpha"
        controller.searchText = "gamma"
        try? await Task.sleep(for: .milliseconds(250))
        #expect(controller.matches.count == 1)
        #expect(controller.matches[0].range.location == 11)
    }

    @Test func invalidRegexReportsErrorInsteadOfNoMatches() async {
        let controller = FindReplaceController()
        controller.bind(text: "alpha", selection: NSRange(location: 0, length: 0))
        controller.useRegex = true
        controller.searchText = "("
        controller.showFind()
        try? await Task.sleep(for: .milliseconds(200))
        #expect(controller.matches.isEmpty)
        #expect(controller.statusMessage == "Invalid regular expression")
    }

    @Test func zeroLengthRegexMatchesAreSkipped() async {
        let controller = FindReplaceController()
        controller.bind(text: "abc", selection: NSRange(location: 0, length: 0))
        controller.useRegex = true
        controller.searchText = "\\b"
        controller.showFind()
        try? await Task.sleep(for: .milliseconds(200))
        #expect(controller.matches.isEmpty)
        #expect(controller.statusMessage == "No matches")
    }

    @Test func replaceCurrentMatch() async {
        let controller = FindReplaceController()
        let text = "foo foo"
        controller.bind(text: text, selection: NSRange(location: 0, length: 0))
        controller.searchText = "foo"
        controller.replaceText = "bar"
        controller.showReplace()
        try? await Task.sleep(for: .milliseconds(200))
        let result = controller.replaceCurrentMatch(in: text, selection: NSRange(location: 0, length: 0))
        #expect(result?.text == "bar foo")
    }

    @Test func replaceAllMatches() async {
        let controller = FindReplaceController()
        let text = "foo foo foo"
        controller.bind(text: text, selection: NSRange(location: 0, length: 0))
        controller.searchText = "foo"
        controller.replaceText = "bar"
        controller.showReplace()
        try? await Task.sleep(for: .milliseconds(200))
        let replaced = controller.replaceAll(in: text)
        #expect(replaced == "bar bar bar")
    }
}
