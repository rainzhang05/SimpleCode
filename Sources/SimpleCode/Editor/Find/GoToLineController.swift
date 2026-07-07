import Foundation

@MainActor
@Observable
final class GoToLineController {
    var isPresented = false
    var lineInput = ""
    var errorMessage: String?

    func show(currentLine: Int) {
        lineInput = "\(currentLine)"
        errorMessage = nil
        isPresented = true
    }

    func dismiss() {
        isPresented = false
        lineInput = ""
        errorMessage = nil
    }

    /// Returns the UTF-16 offset for the requested line and optional column, or nil when invalid.
    func resolve(lineStartIndex: LineStartIndex, lineCount: Int, text: String) -> Int? {
        let trimmed = lineInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2,
              let line = Int(parts[0]),
              line >= 1,
              line <= max(1, lineCount) else {
            errorMessage = "Enter a line between 1 and \(max(1, lineCount))."
            return nil
        }

        let column: Int?
        if parts.count == 2 {
            guard let parsedColumn = Int(parts[1]), parsedColumn >= 1 else {
                errorMessage = "Enter a positive column."
                return nil
            }
            column = parsedColumn
        } else {
            column = nil
        }

        errorMessage = nil
        let lineStart = lineStartIndex.lineStartUTF16Offset(forLine: line)
        guard let column else { return lineStart }

        let lineEnd = lineContentEndUTF16Offset(forLine: line, lineStartIndex: lineStartIndex, lineCount: lineCount, text: text)
        return min(lineStart + column - 1, lineEnd)
    }

    private func lineContentEndUTF16Offset(
        forLine line: Int,
        lineStartIndex: LineStartIndex,
        lineCount: Int,
        text: String
    ) -> Int {
        let ns = text as NSString
        guard line < lineCount else { return ns.length }
        let nextLineStart = lineStartIndex.lineStartUTF16Offset(forLine: line + 1)
        guard nextLineStart > 0 else { return ns.length }
        if nextLineStart >= 2,
           ns.character(at: nextLineStart - 2) == 13,
           ns.character(at: nextLineStart - 1) == 10 {
            return nextLineStart - 2
        }
        return nextLineStart - 1
    }
}
