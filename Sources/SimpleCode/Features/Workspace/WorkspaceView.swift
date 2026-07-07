import SwiftUI

struct WorkspaceView: View {
    @Bindable var workspace: WorkspaceModel
    var onCloseWorkspace: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                if workspace.isSidebarVisible {
                    FileTreeSidebarView(workspace: workspace)
                        .frame(minWidth: 180, idealWidth: 230, maxWidth: 420)
                }

                VSplitView {
                    VStack(spacing: 0) {
                        if !workspace.openDocuments.sessions.isEmpty {
                            EditorTabStripView(workspace: workspace)
                        }
                        editorArea
                    }
                    .frame(minHeight: 200, maxHeight: .infinity)

                    TerminalPanelView(session: workspace.terminal, isVisible: workspace.isTerminalVisible) {
                        workspace.toggleTerminal()
                    }
                    .frame(
                        minHeight: workspace.isTerminalVisible ? WorkspaceModel.minimumTerminalHeight : 1,
                        idealHeight: workspace.terminalHeight,
                        maxHeight: workspace.isTerminalVisible ? WorkspaceModel.maximumTerminalHeight : workspace.terminalHeight
                    )
                    .opacity(workspace.isTerminalVisible ? 1 : 0)
                    .clipped()
                    .allowsHitTesting(workspace.isTerminalVisible)
                    .accessibilityHidden(!workspace.isTerminalVisible)
                }
            }

            WorkspaceStatusBar(workspace: workspace)
        }
        .toolbar {
            WorkspaceToolbar(workspace: workspace, onCloseWorkspace: {
                workspace.requestCloseWorkspace(onConfirmed: onCloseWorkspace)
            })
        }
        .navigationTitle(workspace.rootURL.lastPathComponent)
        .task {
            await workspace.bootstrapDocumentsIfNeeded()
            await workspace.bootstrapAfterOpen()
        }
        .onChange(of: workspace.appSettings.revision) { _, _ in
            workspace.syncFileTreeFromSettings()
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
