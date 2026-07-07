import Foundation

/// Serializes document text and writes atomically while preserving POSIX permissions.
enum FileContentWriter {
    struct WriteRequest: Sendable {
        let url: URL
        let text: String
        let encoding: TextEncodingMode
        let includeBOM: Bool
        let lineEnding: LineEndingMode
    }

    static func serialize(_ request: WriteRequest) throws -> Data {
        let normalized = normalizeLineEndings(request.text, mode: request.lineEnding)
        let encoding = request.encoding.stringEncoding
        guard var data = normalized.data(using: encoding) else {
            throw FileOperationError.unsupportedEncoding
        }

        if request.includeBOM {
            switch request.encoding {
            case .utf8WithBOM:
                data = Data([0xEF, 0xBB, 0xBF]) + data
            case .utf16LittleEndian:
                data = Data([0xFF, 0xFE]) + data
            case .utf16BigEndian:
                data = Data([0xFE, 0xFF]) + data
            default:
                break
            }
        }
        return data
    }

    static func writeAtomically(_ request: WriteRequest) throws -> FileOperationResult {
        let data = try serialize(request)
        let fm = FileManager.default
        let writeURL = resolvedWriteURL(for: request.url)
        let directory = writeURL.deletingLastPathComponent()
        let tempURL = directory.appendingPathComponent(".simplecode-\(UUID().uuidString).tmp")

        var attributes: [FileAttributeKey: Any] = [:]
        if fm.fileExists(atPath: writeURL.path),
           let existing = try? fm.attributesOfItem(atPath: writeURL.path) {
            if let permissions = existing[.posixPermissions] {
                attributes[.posixPermissions] = permissions
            }
        }

        do {
            try data.write(to: tempURL)
            if !attributes.isEmpty {
                try fm.setAttributes(attributes, ofItemAtPath: tempURL.path)
            }

            if fm.fileExists(atPath: writeURL.path) {
                _ = try fm.replaceItemAt(writeURL, withItemAt: tempURL)
            } else {
                try fm.moveItem(at: tempURL, to: writeURL)
            }
        } catch {
            try? fm.removeItem(at: tempURL)
            throw FileOperationError.saveFailed(error.localizedDescription)
        }

        return FileOperationResult(url: request.url)
    }

    private static func resolvedWriteURL(for url: URL) -> URL {
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else {
            return url
        }
        return URL(fileURLWithPath: destination, isDirectory: false)
    }

    private static func normalizeLineEndings(_ text: String, mode: LineEndingMode) -> String {
        let unified = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        switch mode {
        case .lf, .mixed:
            return unified
        case .crlf:
            return unified.replacingOccurrences(of: "\n", with: "\r\n")
        case .cr:
            return unified.replacingOccurrences(of: "\n", with: "\r")
        }
    }
}
