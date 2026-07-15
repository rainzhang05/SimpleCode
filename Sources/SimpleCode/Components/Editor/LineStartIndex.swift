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
        let firstLineStartAfterEditStart = firstIndex(after: editStart)
        let removedLineStart = firstLineStartAfterEditStart < lineStartOffsets.count
            && lineStartOffsets[firstLineStartAfterEditStart] <= editEnd
        let touchesPotentialCRLFBoundary = containsLineStart(at: editStart + 1)
            || containsLineStart(at: editEnd + 1)
        if insertedText.contains(where: { $0 == "\n" || $0 == "\r" })
            || removedLineStart
            || touchesPotentialCRLFBoundary {
            rebuild(from: fullTextFallback())
            return
        }

        guard delta != 0 else { return }

        let firstShiftedIndex = max(1, firstIndex(after: editEnd))
        for index in firstShiftedIndex..<lineStartOffsets.count {
            lineStartOffsets[index] += delta
        }

        if lineStartOffsets.first != 0
            || lineStartOffsets.last.map({ $0 > fullLength }) == true {
            rebuild(from: fullTextFallback())
        }
    }

    private func containsLineStart(at offset: Int) -> Bool {
        let index = firstIndex(notBefore: offset)
        return index < lineStartOffsets.count && lineStartOffsets[index] == offset
    }

    private func firstIndex(after offset: Int) -> Int {
        var low = 0
        var high = lineStartOffsets.count
        while low < high {
            let middle = low + (high - low) / 2
            if lineStartOffsets[middle] <= offset {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    private func firstIndex(notBefore offset: Int) -> Int {
        var low = 0
        var high = lineStartOffsets.count
        while low < high {
            let middle = low + (high - low) / 2
            if lineStartOffsets[middle] < offset {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
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
        var offset = 0
        var previousWasCR = false
        
        for codeUnit in text.utf16 {
            offset += 1
            if previousWasCR {
                previousWasCR = false
                if codeUnit == 10 {
                    starts[starts.count - 1] = offset
                    continue
                }
            }
            
            if codeUnit == 10 {
                starts.append(offset)
            } else if codeUnit == 13 {
                starts.append(offset)
                previousWasCR = true
            }
        }
        return starts
    }
}
