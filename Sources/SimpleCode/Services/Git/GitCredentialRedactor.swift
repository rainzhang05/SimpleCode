import Foundation

enum GitCredentialRedactor {
    static func redactText(_ input: String) -> String {
        var result = input
        // https://user:token@host
        let pattern = #"https?://[^/\s:@]+:[^@\s]+@"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "https://REDACTED@")
        }
        return result
    }
}
