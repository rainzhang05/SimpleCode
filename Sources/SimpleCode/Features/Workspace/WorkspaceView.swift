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
        .sheet(item: Binding(
            get: { workspace.pendingCreation },
            set: { workspace.pendingCreation = $0 }
        )) { pending in
            FileCreationSheet(
                pending: pending,
                validationError: { name in
                    workspace.creationValidationError(for: name, in: pending.directory)
                },
                onCreate: { name in
                    Task { await workspace.createPendingItem(named: name) }
                },
                onCancel: {
                    workspace.pendingCreation = nil
                }
            )
        }
    }

    private var workspaceSurface: some View {
        GeometryReader { proxy in
            Group {
                if proxy.size.width >= 980 {
                    wideWorkspaceSurface
                } else {
                    compactWorkspaceSurface
                }
            }
        }
        .background(ColorRole.editorBackground)
        .clipped()
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: workspace.isSidebarVisible)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: workspace.isTerminalVisible)
    }

    @ViewBuilder
    private var wideWorkspaceSurface: some View {
        if workspace.isSidebarVisible {
            HSplitView {
                sidebar
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
                workspaceContent
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            workspaceContent
        }
    }

    private var compactWorkspaceSurface: some View {
        ZStack(alignment: .topLeading) {
            workspaceContent
            if workspace.isSidebarVisible {
                sidebar
                    .frame(width: 300)
                    .transition(panelTransition(edge: .leading))
                    .zIndex(2)
            }
        }
    }

    private var sidebar: some View {
        FileTreeSidebarView(workspace: workspace)
            .padding(Spacing.small)
    }

    private var workspaceContent: some View {
        VSplitView {
            editorShell
                .frame(minHeight: 220, maxHeight: .infinity)
            // Keep one terminal host in the same view hierarchy while hiding or
            // revealing the dock. Replacing a live SwiftTerm view can otherwise
            // leave its local shell process behind without an owner.
            terminalDock(isVisible: workspace.isTerminalVisible)
                .frame(
                    minHeight: workspace.isTerminalVisible ? WorkspaceModel.minimumTerminalHeight : 1,
                    idealHeight: workspace.isTerminalVisible ? workspace.terminalHeight : 1,
                    maxHeight: workspace.isTerminalVisible ? WorkspaceModel.maximumTerminalHeight : 1
                )
                .opacity(workspace.isTerminalVisible ? 1 : 0.001)
                .allowsHitTesting(workspace.isTerminalVisible)
                .accessibilityHidden(!workspace.isTerminalVisible)
                .clipped()
        }
    }

    private func terminalDock(isVisible: Bool) -> some View {
        TerminalPanelView(
            session: workspace.terminal,
            typography: workspace.appSettings.typography,
            terminalSettings: workspace.appSettings.terminal,
            isVisible: isVisible
        ) {
            workspace.toggleTerminal()
        }
        .padding(.horizontal, Spacing.small)
        .padding(.bottom, isVisible ? Spacing.small : 0)
    }

    private var editorShell: some View {
        VStack(spacing: 0) {
            if !workspace.openDocuments.sessions.isEmpty {
                EditorTabStripView(workspace: workspace)
            }
            editorArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func panelTransition(edge: Edge) -> AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .move(edge: edge).combined(with: .opacity)
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
            .accessibilityIdentifier("workspace.editorPlaceholder")
        }
    }
}

private struct FileCreationSheet: View {
    let pending: WorkspaceModel.PendingCreation
    let validationError: (String) -> String?
    let onCreate: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @FocusState private var isNameFocused: Bool

    init(
        pending: WorkspaceModel.PendingCreation,
        validationError: @escaping (String) -> String?,
        onCreate: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.pending = pending
        self.validationError = validationError
        self.onCreate = onCreate
        self.onCancel = onCancel
        _name = State(initialValue: pending.name)
    }

    private var error: String? {
        validationError(name)
    }

    private var canCreate: Bool {
        error == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Label(pending.kind.title, systemImage: pending.kind == .file ? "doc.badge.plus" : "folder.badge.plus")
                .font(.headline)

            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .onSubmit(commit)
                    .accessibilityIdentifier("fileTree.creationNameField")

                Text(pending.directory.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("fileTree.creationError")
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
                    .accessibilityIdentifier("fileTree.creationConfirm")
            }
        }
        .padding(Spacing.large)
        .frame(width: 420)
        .task {
            isNameFocused = true
        }
        .accessibilityIdentifier("fileTree.creationSheet")
    }

    private func commit() {
        guard canCreate else { return }
        onCreate(name)
    }
}
