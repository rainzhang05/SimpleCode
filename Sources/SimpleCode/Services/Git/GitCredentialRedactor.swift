import Foundation

enum GitCredentialRedactor {
    static func redactURL(_ input: String) -> String {
        guard let url = URL(string: input), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return redactSCPLike(input)
        }
        if components.user != nil {
            components.user = "REDACTED"
            components.password = nil
        }
        return components.string ?? input
    }

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

    private static func redactSCPLike(_ input: String) -> String {
        input
    }
}
