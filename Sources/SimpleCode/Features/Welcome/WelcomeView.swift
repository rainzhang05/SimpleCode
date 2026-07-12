import SwiftUI

struct RecentWorkspacePresentation: Equatable, Sendable {
    enum Availability: Equatable, Sendable {
        case available
        case unavailable
    }

    let name: String
    let availability: Availability

    init(record: WorkspaceRecord) {
        name = record.displayName
        availability = record.isUnavailable ? .unavailable : .available
    }
}

/// The welcome screen shown when no workspace is open. The three primary actions
/// are the strongest visual elements on screen, per the design direction; the
/// recent-workspaces area stays secondary and bounded even when it has content.
struct WelcomeView: View {
    @Bindable var appModel: AppModel

    @State private var isShowingNewFolderSheet = false
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
                    appModel.showCloneSheet = true
                }
            }
            .padding(.horizontal, Spacing.xLarge)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            RecentWorkspacesList(appModel: appModel)
                .frame(maxWidth: 560)

            Spacer(minLength: Spacing.xLarge)
        }
        .frame(minWidth: 640, minHeight: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorRole.chromeFallback.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("welcome.root")
        .fileImporter(isPresented: $isChoosingExistingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                appModel.openWorkspace(at: url)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $isShowingNewFolderSheet) {
            NewFolderSheet(
                onCreate: { url in
                    isShowingNewFolderSheet = false
                    appModel.openWorkspace(at: url)
                },
                onCancel: { isShowingNewFolderSheet = false }
            )
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
        .glassPanel(cornerRadius: CornerRadius.card, interactive: true)
        .pointingHandCursor()
        .accessibilityLabel(title)
        .accessibilityIdentifier("welcome.action.\(identifierSuffix)")
    }

    private var identifierSuffix: String {
        switch title {
        case "Create a New Folder": "createFolder"
        case "Open an Existing Folder": "openFolder"
        case "Clone a Git Repository": "cloneRepository"
        default: title.replacingOccurrences(of: " ", with: "")
        }
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
                    .pointingHandCursor()
                    .font(.system(size: 11))
                    .accessibilityIdentifier("welcome.clearRecentWorkspaces")
                }
            }

            if appModel.recentWorkspaces.records.isEmpty {
                Text("No recent workspaces")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 46, alignment: .center)
                    .glassPanel(cornerRadius: CornerRadius.control)
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.xSmall) {
                        ForEach(appModel.recentWorkspaces.records) { record in
                            RecentWorkspaceRow(record: record, appModel: appModel)
                        }
                    }
                }
                .frame(maxHeight: 208)
                .accessibilityIdentifier("welcome.recentWorkspaces.scroll")
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("welcome.recentWorkspaces")
    }
}

private struct RecentWorkspaceRow: View {
    let record: WorkspaceRecord
    let appModel: AppModel

    private var presentation: RecentWorkspacePresentation {
        RecentWorkspacePresentation(record: record)
    }

    var body: some View {
        Button {
            open()
        } label: {
            HStack(spacing: Spacing.small) {
                Image(systemName: "folder")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                Text(presentation.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Circle()
                    .fill(availabilityColor)
                    .frame(width: 6, height: 6)
                    .help(availabilityLabel)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.small)
            .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46)
            .contentShape(RoundedRectangle(cornerRadius: CornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: CornerRadius.control, style: .continuous))
        .glassPanel(cornerRadius: CornerRadius.control, interactive: true)
        .accessibilityLabel(presentation.name)
        .accessibilityValue(availabilityLabel)
        .accessibilityIdentifier("welcome.recentWorkspaces.row.\(presentation.name)")
        .contextMenu {
            Button("Remove from Recents") {
                appModel.recentWorkspaces.remove(id: record.id)
            }
        }
        .accessibilityAction(named: Text("Remove from Recents")) {
            appModel.recentWorkspaces.remove(id: record.id)
        }
    }

    private var availabilityLabel: String {
        presentation.availability == .available ? "Available" : "Unavailable"
    }

    private var availabilityColor: Color {
        presentation.availability == .available
            ? Color.secondary.opacity(0.35)
            : Color.orange.opacity(0.85)
    }

    private func open() {
        guard let url = appModel.recentWorkspaces.resolvedURL(for: record.id) else { return }
        appModel.openWorkspace(at: url)
    }
}
