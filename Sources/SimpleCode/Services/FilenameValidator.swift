import Foundation

enum FilenameValidator {
    static func validate(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Name cannot be empty." }
        guard trimmed != "." && trimmed != ".." else { return "Name cannot be '.' or '..'." }
        if trimmed.contains("/") || trimmed.contains(":") {
            return "Name cannot contain path separators."
        }
        return nil
    }
}
