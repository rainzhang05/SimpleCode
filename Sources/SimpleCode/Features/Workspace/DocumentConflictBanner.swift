import SwiftUI

struct DocumentConflictBanner: View {
    @Bindable var session: EditorDocumentSession
    var onReload: () -> Void
    var onDismiss: () -> Void
    var onSaveAs: () -> Void
    var onCloseTab: () -> Void

    var body: some View {
        HStack(spacing: Spacing.small) {
            Image(systemName: iconName)
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
            Spacer()
            bannerButtons
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.xSmall)
        .background(Color.orange.opacity(0.12))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.orange.opacity(0.3)).frame(height: 1)
        }
        .accessibilityIdentifier("editor.conflictBanner")
    }

    private var iconName: String {
        switch session.externalChangeState {
        case .deleted: return "trash"
        default: return "arrow.triangle.2.circlepath"
        }
    }

    private var message: String {
        switch session.externalChangeState {
        case .none: return ""
        case .cleanReloadAvailable:
            return "“\(session.displayName)” changed on disk."
        case .dirtyConflict:
            return "“\(session.displayName)” changed on disk while you were editing."
        case .deleted:
            return "“\(session.displayName)” was deleted on disk."
        }
    }

    @ViewBuilder
    private var bannerButtons: some View {
        switch session.externalChangeState {
        case .none:
            EmptyView()
        case .cleanReloadAvailable:
            Button("Reload") { onReload() }
                .controlSize(.small)
                .pointingHandCursor()
            Button("Dismiss") { onDismiss() }
                .controlSize(.small)
                .pointingHandCursor()
        case .dirtyConflict:
            Button("Reload from Disk") { onReload() }
                .controlSize(.small)
                .pointingHandCursor()
            Button("Keep Editing") { onDismiss() }
                .controlSize(.small)
                .pointingHandCursor()
            Button("Save As…") { onSaveAs() }
                .controlSize(.small)
                .pointingHandCursor()
        case .deleted:
            Button("Save As…") { onSaveAs() }
                .controlSize(.small)
                .pointingHandCursor()
            Button("Close Tab") { onCloseTab() }
                .controlSize(.small)
                .pointingHandCursor()
        }
    }
}
