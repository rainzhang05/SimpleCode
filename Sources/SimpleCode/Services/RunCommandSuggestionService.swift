import Foundation

actor RunCommandSuggestionService {
    private let fileManager: FileManager
    private let maxMetadataBytes = 65_536

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func suggest(rootURL: URL) -> RunCommandSuggestion? {
        let root = rootURL.standardizedFileURL

        if fileExists(root.appendingPathComponent("Package.swift")) {
            return RunCommandSuggestion(command: "swift run", reason: "Swift Package Manager project", confidence: .high)
        }
        if fileExists(root.appendingPathComponent("Cargo.toml")) {
            return RunCommandSuggestion(command: "cargo run", reason: "Rust Cargo project", confidence: .high)
        }
        if fileExists(root.appendingPathComponent("go.mod")) {
            return RunCommandSuggestion(command: "go run .", reason: "Go module", confidence: .high)
        }
        if hasMakefile(in: root) {
            return RunCommandSuggestion(command: "make", reason: "Makefile present", confidence: .high)
        }
        if let python = suggestPython(root: root) {
            return python
        }
        if let node = suggestNode(root: root) {
            return node
        }
        if fileExists(root.appendingPathComponent("gradlew")) {
            return RunCommandSuggestion(command: "./gradlew run", reason: "Gradle wrapper present", confidence: .medium)
        }
        if fileExists(root.appendingPathComponent("pom.xml")) {
            return RunCommandSuggestion(
                command: "mvn compile exec:java",
                reason: "Maven project (verify main class configuration)",
                confidence: .medium
            )
        }
        if hasXcodeProject(in: root) {
            return RunCommandSuggestion(
                command: nil,
                reason: "Xcode project detected — configure an xcodebuild command with the correct scheme",
                confidence: .guidance
            )
        }
        return nil
    }

    private func fileExists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    private func hasMakefile(in root: URL) -> Bool {
        for name in ["Makefile", "makefile", "GNUmakefile"] {
            if fileExists(root.appendingPathComponent(name)) { return true }
        }
        return false
    }

    private func hasXcodeProject(in root: URL) -> Bool {
        guard let contents = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return false
        }
        return contents.contains { url in
            let ext = url.pathExtension.lowercased()
            return ext == "xcodeproj" || ext == "xcworkspace"
        }
    }

    private func suggestPython(root: URL) -> RunCommandSuggestion? {
        if fileExists(root.appendingPathComponent("pyproject.toml"))
            || fileExists(root.appendingPathComponent("requirements.txt")) {
            if let entry = unambiguousPythonEntry(in: root) {
                return RunCommandSuggestion(
                    command: "python3 \(entry)",
                    reason: "Python project with entry file \(entry)",
                    confidence: .medium
                )
            }
            return nil
        }
        if let entry = unambiguousPythonEntry(in: root) {
            return RunCommandSuggestion(
                command: "python3 \(entry)",
                reason: "Single Python entry file at project root",
                confidence: .medium
            )
        }
        return nil
    }

    private func unambiguousPythonEntry(in root: URL) -> String? {
        guard let contents = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return nil
        }
        let pyFiles = contents.filter { $0.pathExtension.lowercased() == "py" }.map(\.lastPathComponent)
        if pyFiles.count == 1, pyFiles[0] == "main.py" {
            return pyFiles[0]
        }
        if pyFiles.count == 1 {
            return pyFiles[0]
        }
        return nil
    }

    private func suggestNode(root: URL) -> RunCommandSuggestion? {
        let packageJSON = root.appendingPathComponent("package.json")
        guard fileExists(packageJSON) else { return nil }

        guard let data = readBoundedFile(at: packageJSON),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = json["scripts"] as? [String: String] else {
            return nil
        }

        let manager = detectPackageManager(in: root)
        let scriptName: String?
        if scripts["dev"] != nil {
            scriptName = "dev"
        } else if scripts["start"] != nil {
            scriptName = "start"
        } else if scripts.count == 1, let only = scripts.keys.first {
            scriptName = only
        } else if scripts["run"] != nil {
            scriptName = "run"
        } else {
            scriptName = nil
        }

        guard let scriptName else { return nil }
        let command: String
        switch manager {
        case .yarn: command = "yarn \(scriptName)"
        case .pnpm: command = "pnpm run \(scriptName)"
        case .bun: command = "bun run \(scriptName)"
        case .npm: command = "npm run \(scriptName)"
        }
        return RunCommandSuggestion(
            command: command,
            reason: "Node.js project with script \"\(scriptName)\"",
            confidence: .high
        )
    }

    private enum PackageManager {
        case npm, yarn, pnpm, bun
    }

    private func detectPackageManager(in root: URL) -> PackageManager {
        if fileExists(root.appendingPathComponent("yarn.lock")) { return .yarn }
        if fileExists(root.appendingPathComponent("pnpm-lock.yaml")) { return .pnpm }
        if fileExists(root.appendingPathComponent("bun.lock"))
            || fileExists(root.appendingPathComponent("bun.lockb")) { return .bun }
        return .npm
    }

    private func readBoundedFile(at url: URL) -> Data? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int,
              size <= maxMetadataBytes else { return nil }
        return try? Data(contentsOf: url)
    }
}
