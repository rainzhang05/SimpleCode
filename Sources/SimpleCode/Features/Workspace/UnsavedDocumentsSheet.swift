import SwiftUI

enum UnsavedCloseAction {
    case save
    case dontSave
    case cancel
}

struct UnsavedDocumentsSheet: View {
    let sessions: [EditorDocumentSession]
    var onAction: (UnsavedCloseAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("Save changes to the following documents before closing?")
                .font(.headline)
                .accessibilityIdentifier("unsaved.sheet.title")
            List(sessions) { session in
                Text(session.displayName)
            }
            .frame(height: min(200, CGFloat(sessions.count) * 28 + 20))
            HStack {
                Spacer()
                Button("Cancel") { onAction(.cancel) }
                    .pointingHandCursor()
                    .accessibilityIdentifier("unsaved.sheet.cancel")
                Button("Don't Save", role: .destructive) { onAction(.dontSave) }
                    .pointingHandCursor()
                    .accessibilityIdentifier("unsaved.sheet.dontSave")
                Button("Save All") { onAction(.save) }.keyboardShortcut(.defaultAction)
                    .pointingHandCursor()
                    .accessibilityIdentifier("unsaved.sheet.saveAll")
            }
        }
        .padding(Spacing.large)
        .frame(width: 420)
        .background(WindowAccessibilityConfigurator(
            title: "Unsaved Documents",
            identifier: "unsaved.sheet.window"
        ))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("unsaved.sheet")
    }
}
