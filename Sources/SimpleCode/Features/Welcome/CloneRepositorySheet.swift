import SwiftUI

struct CloneRepositorySheet: View {
    @Bindable var controller: GitCloneController
    var onCancel: () -> Void

    @State private var isChoosingDestination = false
    @State private var showDiagnostics = false
    @State private var folderNameEdited = false

    var body: some View {
        if AppTestingSupport.isUITesting(launchConfiguration: .parse()) {
            sheetContent
        } else {
            sheetContent
                .fileImporter(isPresented: $isChoosingDestination, allowedContentTypes: [.folder]) { result in
                    if case .success(let url) = result {
                        controller.parentURL = url
                    }
                }
        }
    }

    private var sheetContent: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("Clone a Git Repository")
                .font(.headline)
                .accessibilityIdentifier("clone.sheet.title")

            switch controller.sheetState {
            case .editing, .validating, .failed:
                editingContent
            case .cloning, .cancelling:
                progressContent
            case .succeeded:
                successContent
            }

            footerButtons
        }
        .padding(Spacing.large)
        .frame(width: 480)
        .background(WindowAccessibilityConfigurator(
            title: "Clone a Git Repository",
            identifier: "clone.sheet.window"
        ))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clone.sheet")
        .onChange(of: controller.repositoryURLText) { _, _ in
            if !folderNameEdited {
                controller.folderName = controller.derivedFolderName
            }
        }
    }

    @ViewBuilder
    private var editingContent: some View {
        TextField("Repository URL", text: $controller.repositoryURLText)
            .textFieldStyle(.roundedBorder)
            .disabled(isBusy)
            .accessibilityIdentifier("clone.sheet.urlField")

        if let warning = controller.credentialWarning {
            Text(warning)
                .font(.system(size: 11))
                .foregroundStyle(.orange)
        }

        HStack {
            Text(controller.parentURL?.path ?? "Choose destination parent…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Choose…") {
                isChoosingDestination = true
            }
            .disabled(isBusy)
            .pointingHandCursor()
            .accessibilityIdentifier("clone.sheet.chooseParent")
        }

        TextField("Folder name", text: $controller.folderName)
            .textFieldStyle(.roundedBorder)
            .disabled(isBusy)
            .onChange(of: controller.folderName) { _, _ in
                folderNameEdited = true
            }
            .accessibilityIdentifier("clone.sheet.folderName")

        if let destination = controller.finalDestinationURL {
            LabeledContent("Clone into") {
                Text(destination.path)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.system(size: 12))
            .accessibilityIdentifier("clone.sheet.destinationPreview")
        }

        if case .failed(let error) = controller.sheetState {
            Text(error.localizedDescription)
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .accessibilityIdentifier("clone.sheet.error")

            if !controller.diagnostics.isEmpty {
                DisclosureGroup("Diagnostics", isExpanded: $showDiagnostics) {
                    ScrollView {
                        Text(controller.diagnostics)
                            .font(.system(size: 10, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 120)
                }
                .font(.system(size: 11))
            }
        }
    }

    @ViewBuilder
    private var progressContent: some View {
        Text(controller.progress.statusMessage)
            .font(.system(size: 12))
            .accessibilityIdentifier("clone.sheet.progressStatus")

        if let percent = controller.progress.percentage {
            ProgressView(value: percent, total: 100)
                .accessibilityIdentifier("clone.sheet.progressBar")
        } else {
            ProgressView()
                .accessibilityIdentifier("clone.sheet.progressBar")
        }

        Text(controller.progress.phase.displayName)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var successContent: some View {
        Text("Repository cloned successfully.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var footerButtons: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) {
                if isBusy {
                    controller.cancelClone()
                } else {
                    onCancel()
                }
            }
            .pointingHandCursor()
            .accessibilityIdentifier("clone.sheet.cancelButton")

            switch controller.sheetState {
            case .cloning, .cancelling:
                Button("Cancel Clone") {
                    controller.cancelClone()
                }
                .pointingHandCursor()
                .accessibilityIdentifier("clone.sheet.cloneButton")
            case .failed:
                Button("Retry") {
                    controller.resetToEditing()
                    controller.startClone()
                }
                .pointingHandCursor()
                .accessibilityIdentifier("clone.sheet.cloneButton")
            case .succeeded:
                EmptyView()
            default:
                Button("Clone") {
                    controller.startClone()
                }
                .buttonStyle(.borderedProminent)
                .pointingHandCursor()
                .disabled(!controller.canClone || isBusy)
                .accessibilityIdentifier("clone.sheet.cloneButton")
            }
        }
    }

    private var isBusy: Bool {
        switch controller.sheetState {
        case .cloning, .cancelling: true
        default: false
        }
    }
}
