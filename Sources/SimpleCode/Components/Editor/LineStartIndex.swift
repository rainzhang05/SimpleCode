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
        guard delta != 0 else { return }

        let editStart = editedRange.location
        let oldLength = editedRange.length - delta
        let editEnd = editStart + max(0, oldLength)

        var index = 1
        while index < lineStartOffsets.count {
            let offset = lineStartOffsets[index]
            if offset > editStart && offset < editEnd {
                lineStartOffsets.remove(at: index)
            } else {
                index += 1
            }
        }

        for i in 1..<lineStartOffsets.count where lineStartOffsets[i] > editStart {
            lineStartOffsets[i] += delta
        }

        if delta > 0 {
            var scanOffset = 0
            let utf16 = Array(insertedText.utf16)
            while scanOffset < utf16.count {
                if utf16[scanOffset] == 10 {
                    insertLineStart(editStart + scanOffset + 1)
                } else if utf16[scanOffset] == 13 {
                    let nextIsLF = scanOffset + 1 < utf16.count && utf16[scanOffset + 1] == 10
                    insertLineStart(editStart + scanOffset + (nextIsLF ? 2 : 1))
                    if nextIsLF { scanOffset += 1 }
                }
                scanOffset += 1
            }
        }

        if lineStartOffsets.first != 0 || lineStartOffsets != lineStartOffsets.sorted() {
            rebuild(from: fullText)
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

    private mutating func insertLineStart(_ offset: Int) {
        guard offset > 0 else { return }
        if lineStartOffsets.contains(offset) { return }
        let insertionIndex = lineStartOffsets.firstIndex(where: { $0 > offset }) ?? lineStartOffsets.endIndex
        lineStartOffsets.insert(offset, at: insertionIndex)
    }

    static func scanLineStarts(in text: String) -> [Int] {
        var starts = [0]
        let utf16 = text.utf16
        var index = utf16.startIndex
        while index < utf16.endIndex {
            let codeUnit = utf16[index]
            if codeUnit == 10 {
                let next = utf16.index(after: index)
                if next < utf16.endIndex {
                    starts.append(utf16.distance(from: utf16.startIndex, to: next))
                }
            } else if codeUnit == 13 {
                let next = utf16.index(after: index)
                if next < utf16.endIndex, utf16[next] == 10 {
                    let afterPair = utf16.index(after: next)
                    if afterPair < utf16.endIndex {
                        starts.append(utf16.distance(from: utf16.startIndex, to: afterPair))
                    }
                    index = afterPair
                    continue
                } else if next < utf16.endIndex {
                    starts.append(utf16.distance(from: utf16.startIndex, to: next))
                }
            }
            index = utf16.index(after: index)
        }
        return starts
    }
}
