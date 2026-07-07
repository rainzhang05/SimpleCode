import Foundation

actor GitCloneService {
    struct CloneRequest: Sendable {
        let repositoryURL: String
        let destinationURL: URL
        let destinationExistedBeforeClone: Bool
    }

    struct CloneResult: Sendable {
        let destinationURL: URL
        let exitCode: Int32
        let diagnostics: String
    }

    private var process: Process?
    private var isCancelled = false
    private var ownership: CloneDestinationOwnership?
    private var diagnostics = ""
    private let maxDiagnosticsBytes = 32_768
    private(set) var lastProcessIdentifier: Int32?

    /// Sanitized diagnostics from the most recent clone attempt.
    func sanitizedDiagnostics() -> String {
        GitCredentialRedactor.redactText(diagnostics)
    }

    func clone(
        request: CloneRequest,
        onProgress: @escaping @Sendable (GitCloneProgress) -> Void
    ) async throws -> CloneResult {
        guard process == nil else { throw GitCloneError.cloneInProgress }

        isCancelled = false
        ownership = CloneDestinationOwnership(
            destinationURL: request.destinationURL,
            existedBeforeClone: request.destinationExistedBeforeClone
        )
        diagnostics = ""
        lastProcessIdentifier = nil

        let gitPath: String
        switch GitExecutableResolver.resolve() {
        case .success(let path): gitPath = path
        case .failure(let error): throw error
        }

        let parent = request.destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let invocation = GitCloneInvocation.makeConfiguration(
            gitExecutablePath: gitPath,
            repositoryURL: request.repositoryURL,
            destinationURL: request.destinationURL
        )

        let process = Process()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments
        process.environment = makeGitEnvironment()
        process.currentDirectoryURL = invocation.currentDirectoryURL

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        self.process = process

        var progressParser = GitCloneProgressParser()
        onProgress(.initial)

        let stderrTask = Task {
            let handle = stderrPipe.fileHandleForReading
            while !Task.isCancelled {
                let data = handle.availableData
                if data.isEmpty { break }
                self.captureDestinationIdentityIfNeeded()
                let progress = progressParser.append(data: data)
                self.appendDiagnostics(data)
                onProgress(progress)
            }
        }

        let stdoutTask = Task {
            let handle = stdoutPipe.fileHandleForReading
            while !Task.isCancelled {
                let data = handle.availableData
                if data.isEmpty { break }
                self.captureDestinationIdentityIfNeeded()
                self.appendDiagnostics(data)
            }
        }

        let identityPollTask = Task {
            while !Task.isCancelled {
                self.captureDestinationIdentityIfNeeded()
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }

        do {
            try process.run()
            lastProcessIdentifier = process.processIdentifier
        } catch {
            stderrTask.cancel()
            stdoutTask.cancel()
            identityPollTask.cancel()
            self.process = nil
            lastProcessIdentifier = nil
            throw GitCloneError.processLaunchFailure(error.localizedDescription)
        }

        await waitForProcessExit(process)

        stderrTask.cancel()
        stdoutTask.cancel()
        identityPollTask.cancel()
        self.process = nil
        lastProcessIdentifier = nil

        if isCancelled {
            await cleanupPartialDestinationIfOwned(processHasExited: true)
            throw GitCloneError.cancelled
        }

        let exitCode = process.terminationStatus
        let sanitized = sanitizedDiagnostics()
        if exitCode != 0 {
            let message = GitCloneErrorClassifier.classify(sanitizedDiagnostics: sanitized, exitCode: exitCode)
            await cleanupPartialDestinationIfOwned(processHasExited: true)
            throw message
        }

        guard FileManager.default.fileExists(atPath: request.destinationURL.path) else {
            throw GitCloneError.nonzeroExit(exitCode, "Clone finished but destination was not found.")
        }

        return CloneResult(
            destinationURL: request.destinationURL,
            exitCode: exitCode,
            diagnostics: sanitized
        )
    }

    /// Cancels the owned git clone process using deliberate signal escalation:
    /// 1. Mark cancelled (blocks new clones)
    /// 2. SIGINT via `interrupt()` — least destructive
    /// 3. Grace period
    /// 4. SIGTERM via `terminate()` if still running
    /// 5. Wait for confirmed exit before cleanup
    func cancel() async {
        isCancelled = true
        guard let process else { return }

        // SIGINT — graceful interruption for git clone.
        process.interrupt()
        try? await Task.sleep(nanoseconds: 500_000_000)

        if process.isRunning {
            // SIGTERM — escalation when interrupt was ignored.
            process.terminate()
        }

        await waitForProcessExit(process, timeoutNanoseconds: 2_000_000_000)

        self.process = nil
        lastProcessIdentifier = nil

        if !process.isRunning {
            await cleanupPartialDestinationIfOwned(processHasExited: true)
        }
    }

    private func captureDestinationIdentityIfNeeded() {
        guard var owned = ownership else { return }
        owned.captureIdentityIfDestinationAppeared()
        ownership = owned
    }

    private func waitForProcessExit(_ process: Process, timeoutNanoseconds: UInt64 = 0) async {
        if !process.isRunning { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let prior = process.terminationHandler
            process.terminationHandler = { proc in
                prior?(proc)
                continuation.resume()
            }
        }

        if timeoutNanoseconds > 0, process.isRunning {
            let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
            while process.isRunning, DispatchTime.now().uptimeNanoseconds < deadline {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    private func cleanupPartialDestinationIfOwned(processHasExited: Bool) async {
        guard var owned = ownership else { return }
        owned.captureIdentityIfDestinationAppeared()
        ownership = owned
        guard owned.canRemovePartialDestination(processHasExited: processHasExited) else { return }

        let destination = owned.destinationURL
        do {
            try FileManager.default.removeItem(at: destination)
        } catch {
            AppLog.git.error("Failed to remove partial clone destination")
        }
    }

    private func appendDiagnostics(_ data: Data) {
        let chunk = String(decoding: data, as: UTF8.self)
        guard !chunk.isEmpty else { return }
        diagnostics += chunk
        if diagnostics.utf8.count > maxDiagnosticsBytes {
            diagnostics = String(diagnostics.suffix(maxDiagnosticsBytes / 2))
        }
    }

    private func makeGitEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        if env["PATH"] == nil {
            env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
        }
        return env
    }
}
