import Foundation

struct FindMatch: Equatable, Sendable {
    let range: NSRange
}

@MainActor
@Observable
final class FindReplaceController {
    var isVisible = false
    var isReplaceMode = false
    var searchText = "" { didSet { scheduleSearch() } }
    var replaceText = ""
    var matchCase = false { didSet { scheduleSearch() } }
    var wholeWord = false { didSet { scheduleSearch() } }
    var useRegex = false { didSet { scheduleSearch() } }
    var selectionOnly = false { didSet { scheduleSearch() } }

    private(set) var matches: [FindMatch] = []
    private(set) var currentMatchIndex: Int?
    private(set) var searchGeneration = 0
    private(set) var statusMessage: String?

    private var searchTask: Task<Void, Never>?
    private var documentText: String = ""
    private var documentSelection: NSRange = NSRange(location: 0, length: 0)
    private var searchErrorMessage: String?
    private var cachedRegex: NSRegularExpression?
    private var cachedRegexKey: String?

    func bind(text: String, selection: NSRange) {
        documentText = text
        documentSelection = selection
        if isVisible {
            scheduleSearch()
        }
    }

    /// Updates the caret/selection without re-copying document text. Full searches
    /// only run when `selectionOnly` is on (search range depends on selection).
    func updateSelection(_ selection: NSRange) {
        documentSelection = selection
        guard isVisible else { return }
        if selectionOnly {
            scheduleSearch()
            return
        }
        guard !matches.isEmpty else { return }
        currentMatchIndex = firstMatchIndex(atOrAfter: selection.location) ?? 0
        statusMessage = matchStatus()
    }

    func showFind() {
        isVisible = true
        scheduleSearch()
    }

    func showReplace() {
        isVisible = true
        isReplaceMode = true
        scheduleSearch()
    }

    func dismiss() {
        isVisible = false
        searchTask?.cancel()
        searchTask = nil
        documentText = ""
        documentSelection = NSRange(location: 0, length: 0)
        matches = []
        currentMatchIndex = nil
        statusMessage = nil
        cachedRegex = nil
        cachedRegexKey = nil
    }

    func findNext() -> NSRange? {
        guard !matches.isEmpty else { return nil }
        let nextIndex: Int
        if let current = currentMatchIndex {
            nextIndex = (current + 1) % matches.count
        } else {
            nextIndex = firstMatchIndex(atOrAfter: documentSelection.location) ?? 0
        }
        currentMatchIndex = nextIndex
        statusMessage = matchStatus()
        return matches[nextIndex].range
    }

    func findPrevious() -> NSRange? {
        guard !matches.isEmpty else { return nil }
        let previousIndex: Int
        if let current = currentMatchIndex {
            previousIndex = (current - 1 + matches.count) % matches.count
        } else {
            previousIndex = lastMatchIndex(before: documentSelection.location) ?? (matches.count - 1)
        }
        currentMatchIndex = previousIndex
        statusMessage = matchStatus()
        return matches[previousIndex].range
    }

    func replaceCurrentMatch(in text: String, selection: NSRange) -> (text: String, selection: NSRange)? {
        guard let result = replaceCurrentEdit(in: text, selection: selection) else { return nil }
        return (documentText, result.selection)
    }

    func replaceCurrentEdit(in text: String, selection: NSRange) -> (edit: TextEdit, selection: NSRange)? {
        guard let index = currentMatchIndex ?? firstMatchIndex(atOrAfter: selection.location),
              matches.indices.contains(index) else { return nil }

        let match = matches[index]
        let replacement = replacementString(for: match, in: text)
        let edit = TextEdit(range: match.range, replacement: replacement)
        let newText = EditorTextSupport.applyEdits([edit], to: text)
        let delta = (replacement as NSString).length - match.range.length
        let newSelection = NSRange(location: match.range.location + delta, length: 0)

        documentText = newText
        documentSelection = newSelection
        searchGeneration += 1
        let generation = searchGeneration
        matches = performSearch(in: newText, selection: newSelection)
        if matches.isEmpty {
            currentMatchIndex = nil
        } else {
            currentMatchIndex = min(index, matches.count - 1)
        }
        statusMessage = generation == searchGeneration ? matchStatus() : statusMessage
        return (edit, newSelection)
    }

    func replaceAll(in text: String) -> String? {
        guard replaceAllEdits(in: text) != nil else { return nil }
        return documentText
    }

    func replaceAllEdits(in text: String) -> (edits: [TextEdit], selection: NSRange)? {
        guard !matches.isEmpty else { return nil }
        let replacementCount = matches.count
        var edits: [TextEdit] = []
        for match in matches {
            let replacement = replacementString(for: match, in: text)
            edits.append(TextEdit(range: match.range, replacement: replacement))
        }
        let newText = EditorTextSupport.applyEdits(edits, to: text)
        documentText = newText
        documentSelection = NSRange(location: 0, length: 0)
        searchGeneration += 1
        matches = performSearch(in: newText, selection: documentSelection)
        currentMatchIndex = matches.isEmpty ? nil : 0
        statusMessage = matchStatus(replacedCount: replacementCount)
        return (edits, documentSelection)
    }

    private func scheduleSearch() {
        guard isVisible else { return }
        searchTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.runSearch(generation: generation)
        }
    }

    private func runSearch(generation: Int) {
        guard generation == searchGeneration else { return }
        let results = performSearch(in: documentText, selection: documentSelection)
        guard generation == searchGeneration else { return }
        matches = results
        if results.isEmpty {
            currentMatchIndex = nil
            statusMessage = searchText.isEmpty ? nil : (searchErrorMessage ?? "No matches")
        } else {
            currentMatchIndex = firstMatchIndex(atOrAfter: documentSelection.location) ?? 0
            statusMessage = matchStatus()
        }
    }

    private func performSearch(in text: String, selection: NSRange) -> [FindMatch] {
        searchErrorMessage = nil
        guard !searchText.isEmpty else { return [] }

        let searchRange: NSRange
        if selectionOnly, selection.length > 0 {
            searchRange = selection
        } else {
            searchRange = NSRange(location: 0, length: (text as NSString).length)
        }

        if useRegex {
            return regexMatches(in: text, range: searchRange)
        }

        var found: [FindMatch] = []
        var location = searchRange.location
        let options: NSString.CompareOptions = matchCase ? [] : [.caseInsensitive]
        let nsText = text as NSString

        while location < NSMaxRange(searchRange) {
            let remaining = NSRange(location: location, length: NSMaxRange(searchRange) - location)
            let range = nsText.range(of: searchText, options: options, range: remaining)
            guard range.location != NSNotFound else { break }
            if wholeWord, !isWholeWord(range, in: nsText) {
                location = range.location + max(1, range.length)
                continue
            }
            found.append(FindMatch(range: range))
            location = range.location + max(1, range.length)
        }
        return found
    }

    private func regexMatches(in text: String, range: NSRange) -> [FindMatch] {
        guard let regex = regexForCurrentSearch() else { return [] }
        let matches = regex.matches(in: text, range: range)
        var found: [FindMatch] = []
        found.reserveCapacity(matches.count)
        for match in matches where match.range.length > 0 {
            found.append(FindMatch(range: match.range))
        }
        return found
    }

    private func isWholeWord(_ range: NSRange, in text: NSString) -> Bool {
        let left = range.location > 0 ? text.character(at: range.location - 1) : 0
        let right = NSMaxRange(range) < text.length ? text.character(at: NSMaxRange(range)) : 0
        return !isWordCharacter(left) && !isWordCharacter(right)
    }

    private func isWordCharacter(_ codeUnit: unichar) -> Bool {
        guard let scalar = UnicodeScalar(codeUnit) else { return false }
        return CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
    }

    private func replacementString(for match: FindMatch, in text: String) -> String {
        guard useRegex else { return replaceText }
        guard let regex = regexForCurrentSearch() else { return replaceText }
        let matched = (text as NSString).substring(with: match.range)
        let matchedRange = NSRange(location: 0, length: (matched as NSString).length)
        return regex.stringByReplacingMatches(
            in: matched,
            options: [],
            range: matchedRange,
            withTemplate: replaceText
        )
    }

    private func regexForCurrentSearch() -> NSRegularExpression? {
        let key = "\(searchText)\u{0}\(matchCase)"
        if cachedRegexKey == key, let cachedRegex {
            return cachedRegex
        }
        let options: NSRegularExpression.Options = matchCase ? [] : [.caseInsensitive]
        guard let regex = try? NSRegularExpression(pattern: searchText, options: options) else {
            searchErrorMessage = "Invalid regular expression"
            cachedRegex = nil
            cachedRegexKey = key
            return nil
        }
        cachedRegex = regex
        cachedRegexKey = key
        return regex
    }

    private func firstMatchIndex(atOrAfter offset: Int) -> Int? {
        matches.firstIndex { $0.range.location >= offset }
    }

    private func lastMatchIndex(before offset: Int) -> Int? {
        matches.lastIndex { $0.range.location < offset }
    }

    private func matchStatus(replacedCount: Int? = nil) -> String? {
        if let replacedCount {
            return "\(replacedCount) replaced"
        }
        guard let currentMatchIndex, !matches.isEmpty else { return "No matches" }
        return "\(currentMatchIndex + 1) of \(matches.count)"
    }
}
