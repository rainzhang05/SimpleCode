import Foundation

enum BinaryDetector {
    /// Conservative binary detection: NUL bytes or a high proportion of control bytes.
    static func isProbablyBinary(_ data: Data, sampleLimit: Int = 8_192) -> Bool {
        guard !data.isEmpty else { return false }
        let sample = data.prefix(sampleLimit)
        if sample.contains(0) { return true }

        var controlCount = 0
        for byte in sample {
            if byte == 9 || byte == 10 || byte == 13 { continue }
            if byte < 32 || byte == 127 { controlCount += 1 }
        }
        return Double(controlCount) / Double(sample.count) > 0.30
    }
}
