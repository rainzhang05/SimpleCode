import Foundation

struct LoadedFileContent: Sendable {
    let text: String
    let encoding: TextEncodingMode
    let hadBOM: Bool
    let lineEnding: LineEndingMode
    let byteCount: Int64
    let modificationDate: Date?
    let fileResourceIdentifier: Data?
    let language: DocumentLanguage
    let openPolicy: FileSizeThresholds.OpenPolicy
}

enum FileLoadError: Error, Equatable, Sendable {
    case fileNotFound
    case permissionDenied
    case binary
    case unsupportedEncoding
    case tooLarge(Int64)
    case readFailed(String)
}

struct FileMetadata: Sendable {
    let byteCount: Int64
    let openPolicy: FileSizeThresholds.OpenPolicy
}

actor FileContentLoader {
    func metadata(for url: URL) throws -> FileMetadata {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw FileLoadError.fileNotFound
        }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        let byteCount = Int64(values?.fileSize ?? 0)
        return FileMetadata(byteCount: byteCount, openPolicy: FileSizeThresholds.openPolicy(forByteCount: byteCount))
    }

    func load(url: URL, choice: LargeFileOpenChoice? = nil) async throws -> LoadedFileContent {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw FileLoadError.fileNotFound
        }

        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey,
            .isRegularFileKey
        ])

        let byteCount = Int64(values?.fileSize ?? 0)
        let policy = FileSizeThresholds.openPolicy(forByteCount: byteCount)

        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            if (error as NSError).code == NSFileReadNoPermissionError {
                throw FileLoadError.permissionDenied
            }
            throw FileLoadError.readFailed(error.localizedDescription)
        }

        if BinaryDetector.isProbablyBinary(data) {
            throw FileLoadError.binary
        }

        guard let detected = TextEncodingDetector.detect(in: data) else {
            throw FileLoadError.unsupportedEncoding
        }

        guard let text = TextEncodingDetector.decode(data, encoding: detected.encoding, hadBOM: detected.hadBOM) else {
            throw FileLoadError.unsupportedEncoding
        }

        let effectivePolicy = effectiveOpenPolicy(base: policy, choice: choice)
        return LoadedFileContent(
            text: text,
            encoding: detected.encoding,
            hadBOM: detected.hadBOM,
            lineEnding: LineEndingDetector.detect(in: text),
            byteCount: byteCount,
            modificationDate: values?.contentModificationDate,
            fileResourceIdentifier: values?.fileResourceIdentifier as? Data,
            language: LanguageDetector.detect(url: url, content: text),
            openPolicy: effectivePolicy
        )
    }

    private func effectiveOpenPolicy(
        base: FileSizeThresholds.OpenPolicy,
        choice: LargeFileOpenChoice?
    ) -> FileSizeThresholds.OpenPolicy {
        guard let choice else { return base }
        switch choice {
        case .openNormally, .openAnyway:
            return base
        case .openWithoutSyntax:
            return .warnLargeFile
        case .openReadOnlyWithoutSyntax:
            return .readOnlyRecommended
        case .cancel:
            return base
        }
    }
}
