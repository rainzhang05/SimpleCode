import Foundation
import Testing
@testable import SimpleCode

@Suite(.serialized)
struct GitCloneServiceTests {
    private func makeTemp() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "GitClone-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func initBareRepo(at url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init", "--bare", url.path]
        process.currentDirectoryURL = url.deletingLastPathComponent()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "test", code: 1)
        }
    }

    @Test func successfulLocalClone() async throws {
        guard case .success = GitExecutableResolver.resolve() else { return }
        let base = try makeTemp()
        let source = base.appending(path: "source.git")
        try initBareRepo(at: source)
        let dest = base.appending(path: "dest")
        let service = GitCloneService()
        let request = GitCloneService.CloneRequest(
            repositoryURL: source.path,
            destinationURL: dest,
            destinationExistedBeforeClone: false
        )
        let result = try await service.clone(request: request) { _ in }
        #expect(FileManager.default.fileExists(atPath: result.destinationURL.path))
    }

    @Test func cancellationPreservesPreExistingDirectory() async throws {
        guard case .success = GitExecutableResolver.resolve() else { return }
        let base = try makeTemp()
        let source = base.appending(path: "source.git")
        try initBareRepo(at: source)
        let dest = base.appending(path: "existing")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try "marker".write(to: dest.appending(path: "marker.txt"), atomically: true, encoding: .utf8)

        let service = GitCloneService()
        let request = GitCloneService.CloneRequest(
            repositoryURL: source.path,
            destinationURL: dest,
            destinationExistedBeforeClone: true
        )
        let task = Task {
            try await service.clone(request: request) { _ in }
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        await service.cancel()
        _ = try? await task.value
        #expect(FileManager.default.fileExists(atPath: dest.appending(path: "marker.txt").path))
    }

    @Test func cancellationDuringStartupIsHandled() async throws {
        guard case .success = GitExecutableResolver.resolve() else { return }
        let base = try makeTemp()
        let source = base.appending(path: "source.git")
        try initBareRepo(at: source)
        let dest = base.appending(path: "cancel-dest")

        let service = GitCloneService()
        let request = GitCloneService.CloneRequest(
            repositoryURL: source.path,
            destinationURL: dest,
            destinationExistedBeforeClone: false
        )
        let cloneTask = Task { try await service.clone(request: request) { _ in } }
        await Task.yield()
        await service.cancel()
        _ = try? await cloneTask.value
        await service.cancel()
        try? FileManager.default.removeItem(at: dest)
    }

    @Test func doubleCancellationIsHarmless() async throws {
        guard case .success = GitExecutableResolver.resolve() else { return }
        let base = try makeTemp()
        let source = base.appending(path: "source.git")
        try initBareRepo(at: source)
        let dest = base.appending(path: "dest2")
        let service = GitCloneService()
        let request = GitCloneService.CloneRequest(
            repositoryURL: source.path,
            destinationURL: dest,
            destinationExistedBeforeClone: false
        )
        let task = Task { try await service.clone(request: request) { _ in } }
        try await Task.sleep(nanoseconds: 100_000_000)
        await service.cancel()
        await service.cancel()
        _ = try? await task.value
    }

    @Test func failureDiagnosticsAvailable() async throws {
        guard case .success = GitExecutableResolver.resolve() else { return }
        let base = try makeTemp()
        let dest = base.appending(path: "dest")
        let service = GitCloneService()
        let request = GitCloneService.CloneRequest(
            repositoryURL: "/nonexistent/repo/path.git",
            destinationURL: dest,
            destinationExistedBeforeClone: false
        )
        do {
            _ = try await service.clone(request: request) { _ in }
            Issue.record("Expected failure")
        } catch {
            let diag = await service.sanitizedDiagnostics()
            #expect(!diag.isEmpty || error is GitCloneError)
        }
    }

    @Test func credentialRedactionInDiagnostics() {
        let redacted = GitCredentialRedactor.redactText("fatal: https://user:secret@github.com failed")
        #expect(!redacted.contains("secret"))
    }
}

struct GitExecutableResolverTests {
    @Test func resolvesGitWhenAvailable() {
        if case .success(let path) = GitExecutableResolver.resolve() {
            #expect(FileManager.default.isExecutableFile(atPath: path))
        }
    }
}
