import SwiftUI

struct WorkspaceView: View {
    @Bindable var workspace: WorkspaceModel
    var onCloseWorkspace: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            workspaceSurface

            WorkspaceStatusBar(workspace: workspace)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace.root")
        .toolbar {
            WorkspaceToolbar(workspace: workspace, onCloseWorkspace: {
                workspace.requestCloseWorkspace(onConfirmed: onCloseWorkspace)
            })
        }
        .navigationTitle(workspace.rootURL.lastPathComponent)
        .task {
            await workspace.bootstrapAfterOpen()
        }
        .onChange(of: workspace.appSettings.files) { _, _ in
            Task {
                await workspace.refreshFileTreeIfSettingsChanged()
            }
        }
        .sheet(isPresented: Binding(
            get: { workspace.runExecution.showTrustSheet },
            set: { if !$0 { workspace.runExecution.cancelTrustPrompt() } }
        )) {
            if let command = workspace.runExecution.pendingTrustCommand {
                WorkspaceTrustSheet(
                    workspacePath: workspace.rootURL.path,
                    command: command,
                    onCancel: { workspace.runExecution.cancelTrustPrompt() },
                    onRunOnce: { workspace.runExecution.runOnceAfterTrustPrompt() },
                    onTrustAndRun: { workspace.runExecution.trustAndRun() }
                )
                .accessibilityIdentifier("trust.sheet")
            }
        }
        .alert("Restart Terminal?", isPresented: Binding(
            get: { workspace.showRestartTerminalConfirmation },
            set: { workspace.showRestartTerminalConfirmation = $0 }
        )) {
            Button("Restart", role: .destructive) {
                workspace.terminal.restart()
                workspace.runExecution.resetStateForNewRun()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restarting terminates the current shell and loses its interactive state (directory, environment, and virtual environments).")
        }
        .confirmationDialog(
            "Select Syntax Language",
            isPresented: $workspace.showLanguagePickerSheet,
            titleVisibility: .visible
        ) {
            ForEach(LanguageRegistry.all, id: \.id) { definition in
                Button(definition.displayName) {
                    workspace.setLanguage(definition.id)
                }
            }
            Button("Cancel", role: .cancel) {
                workspace.showLanguagePickerSheet = false
            }
        } message: {
            Text("Choose how SimpleCode should color and indent the active document.")
        }
        .sheet(isPresented: Binding(
            get: { workspace.unsavedSessionsForSheet != nil },
            set: { if !$0 { workspace.unsavedSessionsForSheet = nil } }
        )) {
            if let sessions = workspace.unsavedSessionsForSheet {
                UnsavedDocumentsSheet(sessions: sessions) { action in
                    Task { await workspace.handleUnsavedSheet(action) }
                }
            }
        }
        .alert("SimpleCode", isPresented: Binding(
            get: { workspace.errorAlertMessage != nil },
            set: { if !$0 { workspace.errorAlertMessage = nil; workspace.pendingDeleteURL = nil } }
        )) {
            if workspace.pendingDeleteURL != nil {
                Button("Move to Trash", role: .destructive) { Task { await workspace.confirmDelete() } }
                Button("Cancel", role: .cancel) { workspace.pendingDeleteURL = nil }
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(workspace.errorAlertMessage ?? "")
        }
        .sheet(item: Binding(
            get: { workspace.openDocuments.pendingLargeFileOpen },
            set: { workspace.openDocuments.pendingLargeFileOpen = $0 }
        )) { pending in
            LargeFileOpenSheet(pending: pending) { choice in
                Task { await workspace.openDocuments.completeLargeFileOpen(choice: choice) }
            }
        }
    }

    @ViewBuilder
    private var editorArea: some View {
        if let session = workspace.openDocuments.activeSession {
            EditorDocumentView(workspace: workspace, session: session, settings: workspace.appSettings) {
                workspace.syncFindBinding()
            }
        } else {
            ContentUnavailableView(
                "No File Open",
                systemImage: "doc.text",
                description: Text("Select a file from the sidebar to begin editing.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
