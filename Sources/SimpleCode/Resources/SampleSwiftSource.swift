import Foundation

/// In-memory sample content for the editor. Not a bundled resource file —
/// kept as a Swift constant to avoid any resource-loading complexity for
/// something this small.
enum SampleSwiftSource {
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
