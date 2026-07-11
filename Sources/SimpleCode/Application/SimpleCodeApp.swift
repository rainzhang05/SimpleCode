import SwiftUI

@main
struct SimpleCodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(appModel: appModel)
                .task { appDelegate.appModel = appModel }
        }
        .defaultSize(width: 1_100, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New File") { appModel.workspace?.beginCreateNewFile() }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(!appModel.isWorkspaceOpen)
                Button("New Folder") { appModel.workspace?.beginCreateNewFolder() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(!appModel.isWorkspaceOpen)
                Button("Open Folder…") { appModel.closeWorkspace() }
                    .disabled(true)
                Divider()
                Button("Clone Git Repository…") {
                    appModel.showCloneSheet = true
                }
                .disabled(appModel.isWorkspaceOpen)
            }

            CommandMenu("Run") {
                Button("Run") { appModel.workspace?.runExecution.run() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(!(appModel.workspace?.runCommands.hasRunnableCommand ?? false))
                Button("Stop") { appModel.workspace?.runExecution.stop() }
                    .keyboardShortcut(".", modifiers: [.control, .command])
                    .disabled(!(appModel.workspace?.runExecution.state.isInterruptible ?? false))
                Divider()
                Button("Clear Terminal") { appModel.workspace?.terminal.clearDisplay() }
                    .disabled(appModel.workspace == nil)
                Button("Restart Terminal…") {
                    appModel.workspace?.showRestartTerminalConfirmation = true
                }
                .disabled(appModel.workspace == nil)
                Divider()
                if appModel.workspace?.trust.isTrusted == true {
                    Button("Mark Workspace as Untrusted") {
                        appModel.workspace?.trust.markUntrusted()
                    }
                    .disabled(appModel.workspace == nil)
                } else {
                    Button("Mark Workspace as Trusted") {
                        appModel.workspace?.trust.markTrusted()
                    }
                    .disabled(appModel.workspace == nil)
                }
            }

            CommandGroup(after: .saveItem) {
                Button("Save") { Task { try? await appModel.workspace?.saveActive() } }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(appModel.workspace?.openDocuments.activeSession == nil)
                Button("Save As…") { Task { await appModel.workspace?.saveAsActive() } }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(appModel.workspace?.openDocuments.activeSession?.fileURL == nil)
                Button("Save All") { Task { try? await appModel.workspace?.saveAll() } }
                    .keyboardShortcut("s", modifiers: [.command, .option])
                    .disabled(appModel.workspace?.openDocuments.dirtySessions().isEmpty ?? true)
                Divider()
                Button("Close Editor") {
                    if let id = appModel.workspace?.openDocuments.activeSessionID {
                        appModel.workspace?.requestCloseTab(sessionID: id)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(appModel.workspace?.openDocuments.activeSession == nil)
                Button("Reopen Closed Editor") { appModel.workspace?.openDocuments.reopenLastClosed() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Reveal Active File in Finder") {
                    if let url = appModel.workspace?.openDocuments.activeSession?.fileURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                .disabled(appModel.workspace?.openDocuments.activeSession?.fileURL == nil)
            }

            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") { appModel.workspace?.toggleSidebar() }
                    .keyboardShortcut("s", modifiers: [.command, .control])
                Button("Toggle Terminal") { appModel.workspace?.toggleTerminal() }
                    .keyboardShortcut("`", modifiers: .command)
                Button("Refresh File Tree") { Task { await appModel.workspace?.fileTree.refresh() } }
                Button("Collapse All Folders") { appModel.workspace?.fileTree.collapseAll() }
                Divider()
                Button("Rename") {
                    if let workspace = appModel.workspace,
                       let (url, name) = workspace.beginRenameSelectedItem() {
                        workspace.pendingRename = WorkspaceModel.PendingRename(url: url, name: name)
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(appModel.workspace?.fileTree.selectedNodeID == nil)
                Divider()
                Button("Toggle Word Wrap") { appModel.workspace?.toggleWordWrap() }
                    .disabled(appModel.workspace == nil)
                Button("Toggle Whitespace") { appModel.workspace?.toggleWhitespace() }
                    .disabled(appModel.workspace == nil)
                Button("Toggle Line Numbers") { appModel.workspace?.toggleLineNumbers() }
                    .disabled(appModel.workspace == nil)
            }

            CommandMenu("Navigate") {
                Button("Next Editor") { appModel.workspace?.activateNextTab() }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Editor") { appModel.workspace?.activatePreviousTab() }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                Button("Reopen Closed Editor") { appModel.workspace?.openDocuments.reopenLastClosed() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Divider()
                Button("Go to Line…") { appModel.workspace?.showGoToLine() }
                    .keyboardShortcut("l", modifiers: .control)
                    .disabled(appModel.workspace?.openDocuments.activeSession == nil)
                Button("Select Language…") { appModel.workspace?.showLanguagePicker() }
                    .disabled(appModel.workspace?.openDocuments.activeSession == nil)
            }

            CommandMenu("Find") {
                Button("Find…") { appModel.workspace?.showFind() }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(appModel.workspace?.openDocuments.activeSession == nil)
                Button("Find and Replace…") { appModel.workspace?.showReplace() }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                    .disabled(appModel.workspace?.openDocuments.activeSession == nil)
                Button("Find Next") { appModel.workspace?.findNext() }
                    .keyboardShortcut("g", modifiers: .command)
                    .disabled(appModel.workspace?.openDocuments.activeSession == nil)
                Button("Find Previous") { appModel.workspace?.findPrevious() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(appModel.workspace?.openDocuments.activeSession == nil)
            }

            CommandMenu("Editor") {
                Button("Toggle Line Comment") { appModel.workspace?.toggleLineComment() }
                    .keyboardShortcut("/", modifiers: .command)
                    .disabled(appModel.workspace?.openDocuments.activeSession == nil)
                Divider()
                Button("Duplicate Line") { appModel.workspace?.duplicateLine() }
                    .keyboardShortcut("d", modifiers: .command)
                    .disabled(appModel.workspace?.openDocuments.activeSession == nil)
                Button("Move Line Up") { appModel.workspace?.moveLineUp() }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                    .disabled(appModel.workspace?.openDocuments.activeSession == nil)
                Button("Move Line Down") { appModel.workspace?.moveLineDown() }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                    .disabled(appModel.workspace?.openDocuments.activeSession == nil)
                Button("Delete Line") { appModel.workspace?.deleteLine() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                    .disabled(appModel.workspace?.openDocuments.activeSession == nil)
                Divider()
                Button("Indent") { appModel.workspace?.indentSelection() }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(appModel.workspace?.openDocuments.activeSession == nil)
                Button("Outdent") { appModel.workspace?.outdentSelection() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(appModel.workspace?.openDocuments.activeSession == nil)
                Button("Convert Indentation to Spaces") { appModel.workspace?.convertIndentToSpaces() }
                    .disabled(appModel.workspace?.openDocuments.activeSession == nil)
                Button("Convert Indentation to Tabs") { appModel.workspace?.convertIndentToTabs() }
                    .disabled(appModel.workspace?.openDocuments.activeSession == nil)
                Button("Trim Trailing Whitespace") { appModel.workspace?.trimTrailingWhitespace() }
                    .disabled(appModel.workspace?.openDocuments.activeSession == nil)
            }

            CommandGroup(after: .newItem) {
                Button("Close Workspace") { appModel.closeWorkspace() }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                    .disabled(!appModel.isWorkspaceOpen)
            }

            CommandGroup(replacing: .help) {
                Button("SimpleCode Help") {
                    AppDocumentation.openBundledMarkdown(named: "README")
                }
                Button("Acknowledgments") {
                    AppDocumentation.openBundledMarkdown(named: "ACKNOWLEDGMENTS")
                }
                Button("License") {
                    AppDocumentation.openBundledLicense()
                }
            }
        }

        Settings {
            SettingsRootView(settings: appModel.appSettings)
        }
    }
}

private struct RootView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        content
            .sheet(isPresented: Binding(
                get: { appModel.showCloneSheet && !appModel.isWorkspaceOpen },
                set: { show in
                    if !show {
                        appModel.gitClone.handleSheetDismiss()
                        appModel.showCloneSheet = false
                    }
                }
            )) {
                CloneRepositorySheet(
                    controller: appModel.gitClone,
                    onCancel: {
                        appModel.gitClone.handleSheetDismiss()
                        appModel.showCloneSheet = false
                    }
                )
            }
    }

    @ViewBuilder
    private var content: some View {
        switch appModel.route {
        case .welcome:
            WelcomeView(appModel: appModel)
        case .workspace(let workspace):
            WorkspaceView(workspace: workspace) {
                appModel.closeWorkspace()
            }
        }
    }
}
