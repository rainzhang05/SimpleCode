import SwiftUI

struct GoToLineView: View {
    @Bindable var controller: GoToLineController
    let lineStartIndex: LineStartIndex
    let lineCount: Int
    let text: String
    var onGoToOffset: (Int) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("Go to Line")
                .font(.headline)
            TextField("Line number", text: $controller.lineInput)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("goto.lineField")
            if let error = controller.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Enter a line between 1 and \(max(1, lineCount)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .pointingHandCursor()
                Button("Go") {
                    if let offset = controller.resolve(lineStartIndex: lineStartIndex, lineCount: lineCount, text: text) {
                        onGoToOffset(offset)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .pointingHandCursor()
                .accessibilityIdentifier("goto.confirm")
            }
        }
        .padding(Spacing.large)
        .frame(width: 320)
    }
}
