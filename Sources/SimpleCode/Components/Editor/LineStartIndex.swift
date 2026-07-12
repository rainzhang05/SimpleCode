import Foundation

/// Incrementally maintained UTF-16 offsets of each line start in a document.
/// Index 0 always holds offset 0 (line 1). Each subsequent entry is the offset
/// of the first code unit on that line.
struct LineStartIndex: Equatable, Sendable {
    private(set) var lineStartOffsets: [Int] = [0]

    var lineCount: Int { lineStartOffsets.count }

    mutating func rebuild(from text: String) {
        lineStartOffsets = Self.scanLineStarts(in: text)
    }

    mutating func applyEdit(
        editedRange: NSRange,
        changeInLength delta: Int,
        insertedText: String,
        fullText: String
    ) {
        applyEdit(
            editedRange: editedRange,
            changeInLength: delta,
            insertedText: insertedText,
            documentLength: (fullText as NSString).length,
            fullTextFallback: { fullText }
        )
    }

    /// Keeps ordinary character edits on the offset-only fast path. The complete
    /// document is requested only for newline/CRLF repairs or an invariant failure.
    mutating func applyEdit(
        editedRange: NSRange,
        changeInLength delta: Int,
        insertedText: String,
        documentLength fullLength: Int,
        fullTextFallback: () -> String
    ) {
        let editStart = max(0, min(editedRange.location, fullLength))
        let oldLength = max(0, editedRange.length - delta)
        let editEnd = editStart + max(0, oldLength)

        // Newline edits are comparatively rare, and rebuilding them is both fast
        // enough and substantially safer than trying to stitch CRLF boundary cases
        // incrementally. Ordinary character edits retain the cheap offset shift.
        let removedLineStart = lineStartOffsets.contains { $0 > editStart && $0 <= editEnd }
        let touchesPotentialCRLFBoundary = lineStartOffsets.contains(editStart + 1)
            || lineStartOffsets.contains(editEnd + 1)
        if insertedText.contains(where: { $0 == "\n" || $0 == "\r" })
            || removedLineStart
            || touchesPotentialCRLFBoundary {
            rebuild(from: fullTextFallback())
            return
        }

        guard delta != 0 else { return }

        for index in 1..<lineStartOffsets.count where lineStartOffsets[index] > editEnd {
            lineStartOffsets[index] += delta
        }

        if lineStartOffsets.first != 0
            || lineStartOffsets.last.map({ $0 > fullLength }) == true
            || lineStartOffsets != lineStartOffsets.sorted() {
            rebuild(from: fullTextFallback())
        }
    }

    func lineNumber(atUTF16Offset offset: Int) -> Int {
        guard !lineStartOffsets.isEmpty else { return 1 }
        let clamped = max(0, offset)
        var low = 0
        var high = lineStartOffsets.count - 1
        var result = 0
        while low <= high {
            let mid = (low + high) / 2
            if lineStartOffsets[mid] <= clamped {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result + 1
    }

    func lineStartUTF16Offset(forLine line: Int) -> Int {
        guard line > 0, line <= lineStartOffsets.count else {
            return lineStartOffsets.last ?? 0
        }
        return lineStartOffsets[line - 1]
    }

    static func scanLineStarts(in text: String) -> [Int] {
        var starts = [0]
        let utf16 = text.utf16
        var index = utf16.startIndex
        while index < utf16.endIndex {
            let codeUnit = utf16[index]
            if codeUnit == 10 {
                let next = utf16.index(after: index)
                starts.append(utf16.distance(from: utf16.startIndex, to: next))
            } else if codeUnit == 13 {
                let next = utf16.index(after: index)
                if next < utf16.endIndex, utf16[next] == 10 {
                    let afterPair = utf16.index(after: next)
                    starts.append(utf16.distance(from: utf16.startIndex, to: afterPair))
                    index = afterPair
                    continue
                } else {
                    starts.append(utf16.distance(from: utf16.startIndex, to: next))
                }
            }
            index = utf16.index(after: index)
        }
        return starts
    }
}
