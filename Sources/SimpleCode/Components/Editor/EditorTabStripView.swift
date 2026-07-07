import SwiftUI

struct EditorTabStripView: View {
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(workspace.openDocuments.sessions) { session in
                    tab(for: session)
                }
            }
            .padding(.horizontal, Spacing.xSmall)
            .padding(.vertical, Spacing.xxSmall)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle().fill(ColorRole.chromeHairline).frame(height: 1)
        }
    }

    private func tab(for session: EditorDocumentSession) -> some View {
        let isActive = workspace.openDocuments.activeSessionID == session.id
        return HStack(spacing: 6) {
            Image(systemName: session.language == .swift ? "swift" : "doc.text")
                .font(.system(size: 11))
            Text(session.displayName)
                .lineLimit(1)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
            if session.isDirty {
                Circle().fill(Color.accentColor).frame(width: 6, height: 6)
            }
            Button {
                workspace.requestCloseTab(sessionID: session.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .opacity(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isActive ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            workspace.openDocuments.activate(session)
            if let url = session.fileURL {
                workspace.fileTree.activeFileURL = url
            }
        }
        .contextMenu {
            Button("Close") { workspace.requestCloseTab(sessionID: session.id) }
            Button("Close Others") { workspace.requestCloseOthers(than: session.id) }
            Button("Close Tabs to the Right") { workspace.requestCloseToRight(of: session.id) }
            Divider()
            Button("Save") { Task { try? await workspace.save(session: session) } }
            Button("Save All") { Task { try? await workspace.saveAll() } }
            Divider()
            if let url = session.fileURL {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.path, forType: .string) }
                Button("Copy Relative Path") {
                    let relative = url.path.replacingOccurrences(of: workspace.rootURL.path + "/", with: "")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(relative, forType: .string)
                }
            }
        }
        .accessibilityIdentifier("editor.tab.\(session.displayName)")
    }
}
