import Foundation

enum ClonePreferencesStore {
    private static let key = "clonePreferences.v1"

    static func lastParentPath(defaults: UserDefaults = .standard) -> URL? {
        guard let path = defaults.string(forKey: key) else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func setLastParentPath(_ url: URL, defaults: UserDefaults = .standard) {
        defaults.set(url.path, forKey: key)
    }
}

enum GitCloneSheetState: Equatable {
    case editing
    case validating
    case cloning
    case cancelling
    case failed(GitCloneError)
    case succeeded
}

@MainActor
@Observable
final class GitCloneController {
    let recentWorkspaces: RecentWorkspaceStore
    let workspaceStateStore: WorkspaceStateStore
    private let clonePreferencesDefaults: UserDefaults

    private let cloneService = GitCloneService()
    private var cloneTask: Task<Void, Never>?
    private var progressThrottleTask: Task<Void, Never>?
    private var pendingProgress: GitCloneProgress?

    var sheetState: GitCloneSheetState = .editing
    var repositoryURLText = ""
    var folderName = ""
    var parentURL: URL?
    var progress = GitCloneProgress.initial
    var diagnostics = ""
    var credentialWarning: String?
    var lastCloneDestination: URL?

    var onCloneSuccess: ((URL) -> Void)?

    init(
        recentWorkspaces: RecentWorkspaceStore,
        workspaceStateStore: WorkspaceStateStore,
        clonePreferencesDefaults: UserDefaults = .standard
    ) {
        self.recentWorkspaces = recentWorkspaces
        self.workspaceStateStore = workspaceStateStore
        self.clonePreferencesDefaults = clonePreferencesDefaults
        self.parentURL = ClonePreferencesStore.lastParentPath(defaults: clonePreferencesDefaults)

        let launch = LaunchConfiguration.parse()
        if let dest = launch.uiTestCloneDestination {
            parentURL = URL(fileURLWithPath: dest, isDirectory: true)
        }
        if let source = launch.uiTestCloneSource {
            repositoryURLText = source
            folderName = GitURLParser.deriveFolderName(from: source)
        }
    }

    var derivedFolderName: String {
        let parsed = GitURLParser.deriveFolderName(from: repositoryURLText)
        return parsed.isEmpty ? folderName : parsed
    }

    var finalDestinationURL: URL? {
        guard let parentURL else { return nil }
        let name = folderName.isEmpty ? derivedFolderName : folderName
        guard !name.isEmpty else { return nil }
        return parentURL.appending(path: name)
    }

    var canClone: Bool {
        sheetState == .editing && finalDestinationURL != nil
            && !repositoryURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func updateFolderNameFromURL() {
        let derived = GitURLParser.deriveFolderName(from: repositoryURLText)
        if !derived.isEmpty, folderName.isEmpty || folderName == derivedFolderName {
            folderName = derived
        }
    }

    func validateDestination() -> GitCloneError? {
        guard let destination = finalDestinationURL else {
            return .invalidDestinationName("Choose a destination folder.")
        }
        let name = destination.lastPathComponent
        if let error = FilenameValidator.validate(name) {
            return .invalidDestinationName(error)
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue {
                let contents = (try? FileManager.default.contentsOfDirectory(atPath: destination.path)) ?? ["."]
                if !contents.isEmpty {
                    return .destinationExists
                }
            } else {
                return .destinationExists
            }
        }
        let parent = destination.deletingLastPathComponent()
        if !FileManager.default.isWritableFile(atPath: parent.path) {
            return .destinationNotWritable
        }
        return nil
    }

    func startClone() {
        guard canClone, cloneTask == nil else { return }
        updateFolderNameFromURL()

        guard case .success(let parsed) = GitURLParser.parse(repositoryURLText) else {
            if case .failure(let error) = GitURLParser.parse(repositoryURLText) {
                sheetState = .failed(error)
            }
            return
        }

        if parsed.hadEmbeddedCredentials {
            credentialWarning = "Credentials in the URL were removed from display. Prefer SSH or a credential helper."
        }

        if let validationError = validateDestination() {
            sheetState = .failed(validationError)
            return
        }

        guard let destination = finalDestinationURL, let parentURL else { return }

        ClonePreferencesStore.setLastParentPath(parentURL, defaults: clonePreferencesDefaults)
        sheetState = .cloning
        progress = .initial
        diagnostics = ""

        let existed = FileManager.default.fileExists(atPath: destination.path)
        let request = GitCloneService.CloneRequest(
            repositoryURL: parsed.normalizedURL,
            destinationURL: destination,
            destinationExistedBeforeClone: existed
        )

        cloneTask = Task { @MainActor in
            do {
                let result = try await cloneService.clone(request: request) { update in
                    Task { @MainActor in
                        self.scheduleProgressUpdate(update)
                    }
                }
                flushProgressUpdate()
                diagnostics = result.diagnostics
                lastCloneDestination = result.destinationURL
                sheetState = .succeeded
                cloneTask = nil
                onCloneSuccess?(result.destinationURL)
            } catch let error as GitCloneError {
                flushProgressUpdate()
                let serviceDiagnostics = await cloneService.sanitizedDiagnostics()
                diagnostics = serviceDiagnostics.isEmpty
                    ? GitCredentialRedactor.redactText(diagnostics)
                    : serviceDiagnostics
                sheetState = .failed(error)
                cloneTask = nil
            } catch {
                flushProgressUpdate()
                diagnostics = await cloneService.sanitizedDiagnostics()
                sheetState = .failed(.nonzeroExit(1, error.localizedDescription))
                cloneTask = nil
            }
        }
    }

    private func scheduleProgressUpdate(_ update: GitCloneProgress) {
        pendingProgress = update
        guard progressThrottleTask == nil else { return }
        progressThrottleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            flushProgressUpdate()
            progressThrottleTask = nil
        }
    }

    private func flushProgressUpdate() {
        if let pendingProgress {
            progress = pendingProgress
            self.pendingProgress = nil
        }
        progressThrottleTask?.cancel()
        progressThrottleTask = nil
    }

    func cancelClone() {
        guard sheetState == .cloning else { return }
        sheetState = .cancelling
        Task {
            await cloneService.cancel()
            sheetState = .editing
            cloneTask = nil
        }
    }

    func resetToEditing() {
        sheetState = .editing
        progress = .initial
        diagnostics = ""
        credentialWarning = nil
    }

    func tearDown() async {
        if sheetState == .cloning || sheetState == .cancelling {
            await cloneService.cancel()
        }
        cloneTask?.cancel()
        cloneTask = nil
        progressThrottleTask?.cancel()
        progressThrottleTask = nil
    }

    func handleSheetDismiss() {
        if sheetState == .cloning {
            cancelClone()
        }
    }
}
