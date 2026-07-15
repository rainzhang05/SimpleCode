import Foundation

enum IndentationEngine {
    /// Computes the text inserted when the user presses Return at `cursorLocation`.
    static func returnKey(
        text: String,
        cursorLocation: Int,
        options: IndentationOptions
    ) -> EditorCommandResult {
        let ns = EditorTextSupport.nsString(text)
        let clamped = max(0, min(cursorLocation, ns.length))
        let currentLine = EditorTextSupport.lineRange(at: clamped, in: text)
        let currentIndent = EditorTextSupport.leadingWhitespace(on: currentLine, in: text)

        let beforeCursor = clamped > currentLine.location
            ? ns.substring(with: NSRange(location: currentLine.location, length: clamped - currentLine.location))
            : ""
        let afterCursor = clamped < currentLine.location + currentLine.length
            ? ns.substring(with: NSRange(location: clamped, length: currentLine.location + currentLine.length - clamped))
            : ""

        let trimmedBefore = beforeCursor.trimmingCharacters(in: .whitespaces)
        let trimmedAfter = afterCursor.trimmingCharacters(in: .whitespaces)

        var newIndent = currentIndent
        var extraIndent = false
        var dedent = false
        var pairAwareBetweenBraces = false

        if shouldIncreaseIndent(before: trimmedBefore, after: trimmedAfter, language: options.language) {
            extraIndent = true
        }

        if shouldDedent(before: trimmedBefore, language: options.language) {
            dedent = true
        }

        if options.language != .python && options.language != .shell {
            pairAwareBetweenBraces = isBetweenEmptyPair(at: clamped, in: text)
        }

        if dedent {
            newIndent = dedentIndent(currentIndent, options: options)
        } else if extraIndent || pairAwareBetweenBraces {
            newIndent += options.indentUnit
        }

        let lineEnding = EditorTextSupport.lineEnding(in: text)
        let insertion: String
        if pairAwareBetweenBraces {
            insertion = lineEnding + newIndent + lineEnding + currentIndent
        } else {
            insertion = lineEnding + newIndent
        }

        let edit = TextEdit(range: NSRange(location: clamped, length: 0), replacement: insertion)
        let newCursor: Int
        if pairAwareBetweenBraces {
            newCursor = clamped + (lineEnding as NSString).length + (newIndent as NSString).length
        } else {
            newCursor = clamped + (insertion as NSString).length
        }

        return EditorCommandResult(
            edits: [edit],
            resultingSelections: [NSRange(location: newCursor, length: 0)]
        )
    }

    private static func shouldIncreaseIndent(
        before: String,
        after: String,
        language: EditorCommandLanguage
    ) -> Bool {
        switch language {
        case .python:
            return isPythonBlockHeader(before) && after.isEmpty
        case .shell:
            if isShellIndentKeyword(before) { return after.isEmpty }
            if before.hasSuffix("{") && after.isEmpty { return true }
            return false
        case .makefile:
            return before.hasSuffix(":") && after.isEmpty
        default:
            if before.hasSuffix("{") || before.hasSuffix("[") || before.hasSuffix("(") {
                return after.isEmpty || after.hasPrefix("}")
                    || after.hasPrefix("]") || after.hasPrefix(")")
            }
            return false
        }
    }

    private static func shouldDedent(
        before: String,
        language: EditorCommandLanguage
    ) -> Bool {
        switch language {
        case .python:
            return firstToken(in: before).map { ["return", "break", "continue", "pass", "raise"].contains($0) } ?? false
        case .shell:
            return firstToken(in: before).map { ["fi", "done", "esac"].contains($0) } ?? false
        default:
            if before.hasSuffix("}") || before.hasSuffix("]") { return true }
            return false
        }
    }

    private static func dedentIndent(_ indent: String, options: IndentationOptions) -> String {
        guard !indent.isEmpty else { return indent }
        if options.usesTabs {
            if indent.hasSuffix("\t") {
                return String(indent.dropLast())
            }
            var spaces = 0
            for ch in indent where ch == " " { spaces += 1 }
            if spaces >= options.tabWidth {
                var result = indent
                var removed = 0
                while removed < options.tabWidth, result.last == " " {
                    result.removeLast()
                    removed += 1
                }
                return result
            }
            return indent
        }
        if indent.count >= options.tabWidth {
            return String(indent.dropLast(options.tabWidth))
        }
        return ""
    }

    private static func isPythonBlockHeader(_ line: String) -> Bool {
        let pattern = #"^\s*(async\s+)?(def|class|if|elif|else|for|while|try|except|finally|with|match|case)\b.*:\s*(#.*)?$"#
        return line.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isShellIndentKeyword(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed == "then" || trimmed == "do" { return true }
        return trimmed.range(of: #";\s*(then|do)\s*$"#, options: .regularExpression) != nil
    }

    private static func firstToken(in line: String) -> String? {
        line.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init)
    }

    private static func isBetweenEmptyPair(at location: Int, in text: String) -> Bool {
        let ns = EditorTextSupport.nsString(text)
        guard location > 0, location < ns.length else { return false }
        let pairs: [(UInt16, UInt16)] = [
            (40, 41),   // ( )
            (91, 93),   // [ ]
            (123, 125), // { }
        ]
        let open = ns.character(at: location - 1)
        let close = ns.character(at: location)
        return pairs.contains { $0.0 == open && $0.1 == close }
    }
}
