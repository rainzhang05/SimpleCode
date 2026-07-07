import SwiftUI

/// The welcome screen shown when no workspace is open. The three primary actions
/// are the strongest visual elements on screen, per the design direction; the
/// recent-workspaces area stays secondary and bounded even when it has content.
struct WelcomeView: View {
    @Bindable var appModel: AppModel

    @State private var isShowingNewFolderSheet = false
    @State private var isShowingCloneSheet = false
    @State private var isChoosingExistingFolder = false
    @State private var errorMessage: String?
    var body: some View {
        VStack(spacing: Spacing.large) {
            Spacer(minLength: Spacing.xLarge)

            VStack(spacing: Spacing.xxSmall) {
                Text("SimpleCode")
                    .accessibilityIdentifier("welcome.title")
                    .font(.system(size: 28, weight: .semibold))
                Text("A lightweight native code editor")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: Spacing.medium) {
                WelcomeActionCard(title: "Create a New Folder", systemImage: "folder.badge.plus") {
                    isShowingNewFolderSheet = true
                }
                WelcomeActionCard(title: "Open an Existing Folder", systemImage: "folder") {
                    isChoosingExistingFolder = true
                }
                WelcomeActionCard(title: "Clone a Git Repository", systemImage: "arrow.down.doc") {
                    isShowingCloneSheet = true
                }
            }
            .padding(.horizontal, Spacing.xLarge)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            RecentWorkspacesList(appModel: appModel)
                .frame(maxWidth: 520)

            Spacer(minLength: Spacing.xLarge)
        }
        .frame(minWidth: 640, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            configureCloneController()
            if appModel.launchConfiguration.showCloneSheet
                || ProcessInfo.processInfo.environment["SIMPLECODE_SHOW_CLONE_SHEET"] == "1"
                || appModel.showCloneSheet {
                isShowingCloneSheet = true
            }
        }
        .onChange(of: appModel.showCloneSheet) { _, show in
            if show { isShowingCloneSheet = true }
        }
        .fileImporter(isPresented: $isChoosingExistingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                appModel.openWorkspace(at: url, provenance: .openedExisting)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $isShowingNewFolderSheet) {
            NewFolderSheet(
                onCreate: { url in
                    isShowingNewFolderSheet = false
                    appModel.openWorkspace(at: url, provenance: .userCreated)
                },
                onCancel: { isShowingNewFolderSheet = false }
            )
        }
        .sheet(isPresented: $isShowingCloneSheet, onDismiss: {
            appModel.gitClone.handleSheetDismiss()
            appModel.showCloneSheet = false
        }) {
            CloneRepositorySheet(
                controller: appModel.gitClone,
                onCancel: {
                    appModel.gitClone.handleSheetDismiss()
                    isShowingCloneSheet = false
                    appModel.showCloneSheet = false
                }
            )
            .onAppear { configureCloneController() }
        }
    }

    private func configureCloneController() {
        appModel.gitClone.onCloneSuccess = { [appModel] destination in
            appModel.handleCloneSuccess(destination: destination)
        }
    }
}

private extension GitCloneSheetState {
    var isBusy: Bool {
        switch self {
        case .cloning, .cancelling: true
        default: false
        }
    }
}

private struct WelcomeActionCard: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.small) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .multilineTextAlignment(.center)
            }
            .frame(width: 168, height: 124)
        }
        .buttonStyle(.plain)
        .glassPanel(cornerRadius: CornerRadius.card, interactive: !reduceMotion)
        .accessibilityIdentifier("welcome.\(title)")
    }
}

private struct RecentWorkspacesList: View {
    let appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            HStack {
                Text("Recent Workspaces")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !appModel.recentWorkspaces.records.isEmpty {
                    Button("Clear All") {
                        appModel.recentWorkspaces.clearAll()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .accessibilityIdentifier("welcome.clearRecentWorkspaces")
                }
            }

            Group {
                if appModel.recentWorkspaces.records.isEmpty {
                    Text("No recent workspaces")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(appModel.recentWorkspaces.records) { record in
                                RecentWorkspaceRow(record: record, appModel: appModel)
                                if record.id != appModel.recentWorkspaces.records.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 176)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.control, style: .continuous))
        }
        .accessibilityIdentifier("welcome.recentWorkspaces")
    }
}

private struct RecentWorkspaceRow: View {
    let record: WorkspaceRecord
    let appModel: AppModel

    var body: some View {
        Button {
            open()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(record.path)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if record.isUnavailable {
                    Text("Unavailable")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove from Recents") {
                appModel.recentWorkspaces.remove(id: record.id)
            }
        }
    }

    private func open() {
        guard let url = appModel.recentWorkspaces.resolvedURL(for: record.id) else { return }
        appModel.openWorkspace(at: url, provenance: .openedExisting)
    }
}
