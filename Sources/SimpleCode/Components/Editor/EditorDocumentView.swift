import SwiftUI

struct EditorDocumentView: View {
    @Bindable var workspace: WorkspaceModel
    @Bindable var session: EditorDocumentSession
    var settings: AppSettingsSnapshot
    var onTextChanged: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if session.externalChangeState != .none {
                DocumentConflictBanner(
                    session: session,
                    onReload: { Task { await workspace.reloadActiveFromDisk() } },
                    onDismiss: { workspace.dismissExternalChange(for: session) },
                    onSaveAs: { Task { await workspace.saveAsActive() } },
                    onCloseTab: { workspace.requestCloseTab(sessionID: session.id) }
                )
            }
            if workspace.findReplace.isVisible {
                FindBarView(
                    controller: workspace.findReplace,
                    onFindNext: { workspace.findNext() },
                    onFindPrevious: { workspace.findPrevious() },
                    onReplace: { workspace.replaceCurrent() },
                    onReplaceAll: { workspace.replaceAll() },
                    onDismiss: { workspace.findReplace.dismiss() }
                )
            }
            editorContent
        }
        .background(ColorRole.editorBackground)
        .onChange(of: session.revision) { _, _ in
            guard workspace.findReplace.isVisible else { return }
            workspace.findReplace.bind(text: session.textStorage.string, selection: session.selectionRange)
        }
        .onChange(of: session.selectionRange) { _, newValue in
            guard workspace.findReplace.isVisible else { return }
            workspace.findReplace.bind(text: session.textStorage.string, selection: newValue)
        }
        .onAppear {
            guard workspace.findReplace.isVisible else { return }
            workspace.findReplace.bind(text: session.textStorage.string, selection: session.selectionRange)
        }
        .sheet(isPresented: Binding(
            get: { workspace.goToLine.isPresented },
            set: { if !$0 { workspace.goToLine.dismiss() } }
        )) {
            GoToLineView(
                controller: workspace.goToLine,
                lineStartIndex: session.lineStartIndex,
                lineCount: session.lineStartIndex.lineCount,
                text: session.textStorage.string,
                onGoToOffset: { workspace.goToLineOffset($0) },
                onCancel: { workspace.goToLine.dismiss() }
            )
        }
    }

    @ViewBuilder
    private var editorContent: some View {
        switch session.loadState {
        case .loading:
            ProgressView("Opening \(session.displayName)…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .binaryPlaceholder:
            BinaryDocumentPlaceholderView(session: session)
        case .error(let message):
            ContentUnavailableView("Could Not Open File", systemImage: "exclamationmark.triangle", description: Text(message))
        case .idle, .loaded:
            CodeEditorRepresentable(
                session: session,
                settings: settings,
                workspace: workspace,
                onTextChanged: onTextChanged
            )
        }
    }
}

struct BinaryDocumentPlaceholderView: View {
    let session: EditorDocumentSession

    var body: some View {
        VStack(spacing: Spacing.medium) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(session.displayName)
                .font(.headline)
            Text(session.fileURL?.pathExtension.uppercased() ?? "Binary")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(ByteCountFormatter.string(fromByteCount: session.lastKnownByteCount, countStyle: .file))
                .font(.caption)
            if let url = session.fileURL {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
