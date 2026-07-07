import SwiftUI

struct FindBarView: View {
    @Bindable var controller: FindReplaceController
    var onFindNext: () -> Void
    var onFindPrevious: () -> Void
    var onReplace: () -> Void
    var onReplaceAll: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: Spacing.small) {
            HStack(spacing: Spacing.small) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Find", text: $controller.searchText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("find.searchField")
                if let status = controller.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 72, alignment: .trailing)
                }
                Button(action: onFindPrevious) {
                    Image(systemName: "chevron.up")
                }
                .help("Find Previous")
                .accessibilityIdentifier("find.previous")
                Button(action: onFindNext) {
                    Image(systemName: "chevron.down")
                }
                .help("Find Next")
                .accessibilityIdentifier("find.next")
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .help("Close")
            }

            if controller.isReplaceMode {
                HStack(spacing: Spacing.small) {
                    Color.clear.frame(width: 16)
                    TextField("Replace", text: $controller.replaceText)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("find.replaceField")
                    Button("Replace", action: onReplace)
                        .accessibilityIdentifier("find.replace")
                    Button("Replace All", action: onReplaceAll)
                        .accessibilityIdentifier("find.replaceAll")
                }
            }

            HStack(spacing: Spacing.medium) {
                Toggle("Match Case", isOn: $controller.matchCase)
                    .toggleStyle(.checkbox)
                Toggle("Whole Word", isOn: $controller.wholeWord)
                    .toggleStyle(.checkbox)
                Toggle("Regex", isOn: $controller.useRegex)
                    .toggleStyle(.checkbox)
                Toggle("Selection Only", isOn: $controller.selectionOnly)
                    .toggleStyle(.checkbox)
            }
            .font(.caption)
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.small)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
