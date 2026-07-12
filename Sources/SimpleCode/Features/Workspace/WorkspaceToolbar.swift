import SwiftUI

/// The workspace window's toolbar. Liquid Glass is provided automatically by the
/// system toolbar material — this file only supplies the content.
struct WorkspaceToolbar: ToolbarContent {
    @Bindable var workspace: WorkspaceModel
    var onCloseWorkspace: () -> Void

    @State private var isRunPopoverPresented = false

    private var hasRunnableCommand: Bool {
        workspace.runCommands.hasRunnableCommand
    }

    private var showStop: Bool {
        workspace.runExecution.state.isInterruptible
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                workspace.toggleSidebar()
            } label: {
                Image(systemName: "sidebar.leading")
            }
            .help("Toggle Sidebar")
            .pointingHandCursor()
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if showStop {
                Button {
                    workspace.runExecution.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .help("Stop (Control-Command-Period)")
                .pointingHandCursor()
                .accessibilityIdentifier("workspace.stopButton")
            }

            Button {
                workspace.runExecution.run()
            } label: {
                Label("Run", systemImage: "play.fill")
            }
            .disabled(!hasRunnableCommand || !workspace.runExecution.state.acceptsRunSubmission)
            .help(hasRunnableCommand ? "Run (Command-R)" : "Configure a run command first")
            .pointingHandCursor()
            .accessibilityIdentifier("workspace.runButton")

            Button {
                isRunPopoverPresented = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .help("Edit Run Command")
            .pointingHandCursor()
            .accessibilityIdentifier("workspace.runConfigButton")
            .sheet(isPresented: $isRunPopoverPresented) {
                RunConfigurationPopover(workspace: workspace, isPresented: $isRunPopoverPresented)
            }

            Button {
                workspace.toggleTerminal()
            } label: {
                Image(systemName: "terminal")
            }
            .help("Toggle Terminal")
            .pointingHandCursor()
            .accessibilityIdentifier("workspace.terminalToggle")
        }

    }
}
