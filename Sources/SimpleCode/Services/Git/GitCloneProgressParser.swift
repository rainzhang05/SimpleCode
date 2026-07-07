import Foundation

struct GitCloneProgressParser: Sendable {
    private var buffer = ""
    private var lastKnownPhase: GitClonePhase = .unknown
    private let maxBufferBytes = 32_768

    private static let phaseOrder: [GitClonePhase: Int] = [
        .unknown: 0,
        .counting: 1,
        .compressing: 2,
        .receiving: 3,
        .resolving: 4,
        .checkingOut: 5,
    ]

    mutating func append(_ chunk: String) -> GitCloneProgress {
        buffer += chunk
        if buffer.utf8.count > maxBufferBytes {
            buffer = String(buffer.suffix(maxBufferBytes / 2))
        }
        return parseLatestLine()
    }

    mutating func append(data: Data) -> GitCloneProgress {
        let chunk = String(decoding: data, as: UTF8.self)
        return append(chunk)
    }

    private mutating func parseLatestLine() -> GitCloneProgress {
        let lines = buffer.components(separatedBy: CharacterSet.newlines)
        let meaningful = lines.last(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            ?? buffer

        let cleaned = meaningful
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var progress = GitCloneProgress.initial
        progress.statusMessage = cleaned.isEmpty ? "Cloning…" : cleaned

        let detectedPhase = detectPhase(from: cleaned)
        progress.phase = monotonicPhase(detectedPhase)

        if let percent = extractPercentage(from: cleaned) {
            progress.percentage = percent
        }

        if let (received, total) = extractObjectCounts(from: cleaned) {
            progress.receivedObjects = received
            progress.totalObjects = total
        }

        return progress
    }

    private mutating func monotonicPhase(_ detected: GitClonePhase) -> GitClonePhase {
        let detectedOrder = Self.phaseOrder[detected] ?? 0
        let lastOrder = Self.phaseOrder[lastKnownPhase] ?? 0
        if detectedOrder >= lastOrder {
            lastKnownPhase = detected
            return detected
        }
        return lastKnownPhase
    }

    private func detectPhase(from cleaned: String) -> GitClonePhase {
        let lower = cleaned.lowercased()
        if lower.contains("counting objects") { return .counting }
        if lower.contains("compressing objects") { return .compressing }
        if lower.contains("receiving objects") { return .receiving }
        if lower.contains("resolving deltas") { return .resolving }
        if lower.contains("checking out") { return .checkingOut }
        return .unknown
    }

    private func extractPercentage(from line: String) -> Double? {
        let pattern = #"(\d+)%"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line),
              let value = Double(line[range]),
              value >= 0, value <= 100 else { return nil }
        return value
    }

    private func extractObjectCounts(from line: String) -> (Int, Int)? {
        let pattern = #"(\d+)/(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let r1 = Range(match.range(at: 1), in: line),
              let r2 = Range(match.range(at: 2), in: line),
              let received = Int(line[r1]),
              let total = Int(line[r2]) else { return nil }
        return (received, total)
    }
}
