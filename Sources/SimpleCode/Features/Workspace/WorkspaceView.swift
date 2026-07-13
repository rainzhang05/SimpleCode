import SwiftUI

enum FileTreeSettingsRefreshPolicy {
    static func shouldRefresh(
        from oldSettings: AppSettingsSnapshot,
        to newSettings: AppSettingsSnapshot
    ) -> Bool {
        oldSettings.files.userExclusions != newSettings.files.userExclusions
    }
}

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
        .onChange(of: workspace.appSettings.snapshot) { oldSettings, newSettings in
            if FileTreeSettingsRefreshPolicy.shouldRefresh(from: oldSettings, to: newSettings) {
                Task {
                    await workspace.refreshFileTreeIfSettingsChanged()
                }
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
            let topInset = min(max(0, proxy.safeAreaInsets.top), max(0, proxy.size.height))
            let contentHeight = WorkspacePanelLayout.contentHeight(
                containerHeight: proxy.size.height,
                topInset: topInset
            )

            ZStack {
                ColorRole.editorBackground

                workspaceLayers(contentHeight: contentHeight)
                    .frame(width: max(0, proxy.size.width), height: contentHeight)
                    .position(
                        x: max(0, proxy.size.width) / 2,
                        y: topInset + contentHeight / 2
                    )
            }
            .frame(width: max(0, proxy.size.width), height: max(0, proxy.size.height))
        }
        .ignoresSafeArea(.container, edges: .top)
        .clipped()
    }

    private func workspaceLayers(contentHeight: CGFloat) -> some View {
        let terminalHeight = WorkspacePanelLayout.fittedTerminalHeight(
            configuredHeight: workspace.terminalHeight,
            availableHeight: contentHeight - (Spacing.small * 2)
        )
        let sidebarReservation = WorkspacePanelLayout.sidebarReservation(
            sidebarWidth: workspace.sidebarWidth,
            panelInset: Spacing.small,
            isVisible: workspace.isSidebarVisible
        )

        return ZStack(alignment: .topLeading) {
            editorShell
                .padding(.leading, sidebarReservation)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: WorkspacePanelLayout.motionDuration),
                    value: workspace.isSidebarVisible
                )

            sidebarOverlay
                .zIndex(2)

            terminalOverlay(height: terminalHeight)
                .zIndex(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebarOverlay: some View {
        FileTreeSidebarView(workspace: workspace)
            .frame(width: workspace.sidebarWidth)
            .padding(.leading, Spacing.small)
            .padding(.top, Spacing.small)
            .padding(.bottom, Spacing.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .offset(
                x: WorkspacePanelLayout.sidebarOffset(
                    sidebarWidth: workspace.sidebarWidth,
                    panelInset: Spacing.small,
                    isVisible: workspace.isSidebarVisible
                )
            )
            .allowsHitTesting(workspace.isSidebarVisible)
            .accessibilityHidden(!workspace.isSidebarVisible)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: WorkspacePanelLayout.motionDuration),
                value: workspace.isSidebarVisible
            )
    }

    private func terminalOverlay(height: CGFloat) -> some View {
        TerminalPanelView(
            session: workspace.terminal,
            settings: workspace.appSettings.snapshot,
            panelHeight: $workspace.terminalHeight,
            isVisible: workspace.isTerminalVisible
        ) {
            workspace.toggleTerminal()
        }
        .frame(height: height)
        .padding(.horizontal, Spacing.small)
        .padding(.bottom, Spacing.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .offset(
            y: WorkspacePanelLayout.terminalOffset(
                terminalHeight: height,
                panelInset: Spacing.small,
                isVisible: workspace.isTerminalVisible
            )
        )
        .allowsHitTesting(workspace.isTerminalVisible)
        .accessibilityHidden(!workspace.isTerminalVisible)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: WorkspacePanelLayout.motionDuration),
            value: workspace.isTerminalVisible
        )
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

    @ViewBuilder
    private var editorArea: some View {
        if let session = workspace.openDocuments.activeSession {
            EditorDocumentView(
                workspace: workspace,
                session: session,
                settings: workspace.appSettings.snapshot
            ) {
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
                    .pointingHandCursor()
                Button("Create", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
                    .pointingHandCursor()
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
