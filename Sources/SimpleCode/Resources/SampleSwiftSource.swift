import Foundation

/// In-memory sample content for the editor spike. Not a bundled resource file —
/// kept as a Swift string constant to avoid any resource-loading complexity for
/// something this small.
enum SampleSwiftSource {
    /// A short, hand-written sample exercising the highlight categories called out
    /// in the brief: keywords, types, function names, strings, numbers, comments,
    /// operators/punctuation.
    static let short = """
    // SimpleCode syntax-highlighting sample.
    import Foundation

    /// A tiny model used only to exercise the highlighter.
    struct Player: Identifiable, Codable {
        let id: UUID
        var name: String
        var score: Int = 0
        private(set) var isActive: Bool = true

        mutating func addPoints(_ amount: Int) {
            guard amount > 0 else { return }
            score += amount
            if score >= 100 {
                isActive = false
            }
        }
    }

    final class Leaderboard {
        private var players: [Player] = []

        func register(_ player: Player) {
            players.append(player)
        }

        func topScorer() -> Player? {
            players.max { $0.score < $1.score }
        }

        func summary() -> String {
            let total = players.reduce(0) { $0 + $1.score }
            return "Players: \\(players.count), Total: \\(total)"
        }
    }

    enum GameError: Error {
        case playerNotFound
        case invalidScore(reason: String)
    }

    func run() async throws {
        let board = Leaderboard()
        for index in 0..<3 {
            var player = Player(id: UUID(), name: "Player \\(index)")
            player.addPoints(index * 42)
            board.register(player)
        }
        print(board.summary())
    }
    """

    /// A large, synthetic Swift source used only for the manual performance check
    /// described in the brief ("continuous typing in a representative Swift file of
    /// at least several thousand lines"). Generated rather than checked in verbatim
    /// so its size is easy to adjust.
    static func generateLarge(targetLineCount: Int = 6_000) -> String {
        var lines: [String] = [
            "// Generated stress-test file — see SampleSwiftSource.generateLarge.",
            "import Foundation",
            ""
        ]
        var index = 0
        while lines.count < targetLineCount {
            lines.append("struct GeneratedModel\(index): Identifiable, Equatable {")
            lines.append("    let id = \(index)")
            lines.append("    var name: String = \"item-\(index)\"")
            lines.append("    var value: Double = \(index).5")
            lines.append("")
            lines.append("    // Computes a derived score for this generated model.")
            lines.append("    func score(multiplier: Int) -> Double {")
            lines.append("        guard multiplier > 0 else { return 0 }")
            lines.append("        let base = value * Double(multiplier)")
            lines.append("        if base > 1_000 {")
            lines.append("            return base / 2")
            lines.append("        }")
            lines.append("        return base + Double(id % 7)")
            lines.append("    }")
            lines.append("}")
            lines.append("")
            index += 1
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
