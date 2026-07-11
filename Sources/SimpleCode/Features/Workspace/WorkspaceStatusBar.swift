import SwiftUI

struct WorkspaceStatusBar: View {
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        HStack(spacing: Spacing.small) {
            Text(workspace.rootURL.path)
                .font(.system(size: 11))
                .foregroundStyle(ColorRole.statusBarText)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if let session = workspace.openDocuments.activeSession {
                Text("Ln \(session.cursorLine), Col \(session.cursorColumn)")

                Menu {
                    ForEach(LanguageRegistry.all, id: \.id) { definition in
                        Button(definition.displayName) {
                            workspace.setLanguage(definition.id)
                        }
                    }
                } label: {
                    Text(session.language.displayName)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .pointingHandCursor()
                .accessibilityLabel("Language")
                .accessibilityIdentifier("status.language")

                Text(session.encoding.displayName)
                Text(session.lineEnding.displayName)
                if session.isReadOnly {
                    Text("Read Only")
                }
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(ColorRole.statusBarText)
        .padding(.horizontal, Spacing.small)
        .frame(height: 22)
        .background(ColorRole.chromeFallback)
        .overlay(alignment: .top) {
            Rectangle().fill(ColorRole.chromeHairline).frame(height: 1)
        }
    }
}
