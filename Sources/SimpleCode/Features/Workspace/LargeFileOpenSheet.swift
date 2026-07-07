import SwiftUI

struct LargeFileOpenSheet: View {
    let pending: PendingLargeFileOpen
    var onChoice: (LargeFileOpenChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("Open Large File")
                .font(.headline)
            Text(pending.url.lastPathComponent)
                .font(.subheadline)
            Text(ByteCountFormatter.string(fromByteCount: pending.byteCount, countStyle: .file))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(explanation)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onChoice(.cancel) }
                ForEach(primaryActions, id: \.title) { action in
                    Button(action.title) { onChoice(action.choice) }
                        .keyboardShortcut(action.isDefault ? .defaultAction : .cancelAction)
                }
            }
        }
        .padding(Spacing.large)
        .frame(width: 440)
        .accessibilityIdentifier("editor.largeFileOpenSheet")
    }

    private var explanation: String {
        switch pending.policy {
        case .normal:
            return ""
        case .warnLargeFile:
            return "This file is larger than 5 MB. Syntax highlighting may affect performance. You can open without highlighting or cancel."
        case .readOnlyRecommended:
            return "This file is larger than 20 MB. Opening read-only without syntax highlighting is recommended."
        }
    }

    private struct SheetAction {
        let title: String
        let choice: LargeFileOpenChoice
        let isDefault: Bool
    }

    private var primaryActions: [SheetAction] {
        switch pending.policy {
        case .normal:
            return [SheetAction(title: "Open", choice: .openNormally, isDefault: true)]
        case .warnLargeFile:
            return [
                SheetAction(title: "Open Normally", choice: .openNormally, isDefault: true),
                SheetAction(title: "Open Without Syntax", choice: .openWithoutSyntax, isDefault: false)
            ]
        case .readOnlyRecommended:
            return [
                SheetAction(title: "Open Read-Only Without Syntax", choice: .openReadOnlyWithoutSyntax, isDefault: true),
                SheetAction(title: "Open Anyway", choice: .openAnyway, isDefault: false)
            ]
        }
    }
}
