import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appModel: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["SIMPLECODE_UI_TESTING"] == "1" else { return }
        bringVisibleWindowsForward()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.bringVisibleWindowsForward()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["SIMPLECODE_UI_TESTING"] == "1" else { return }
        bringVisibleWindowsForward()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if ProcessInfo.processInfo.environment["SIMPLECODE_UI_TESTING"] == "1" {
            return false
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // A clone can be active while the welcome window is showing, so begin its
        // bounded cancellation before checking for a workspace. Never make AppKit
        // wait for the child process here.
        appModel?.beginTerminationCleanup()
        guard let workspace = appModel?.workspace else { return .terminateNow }
        let dirty = workspace.openDocuments.dirtySessions()
        if dirty.isEmpty {
            workspace.tearDown()
            return .terminateNow
        }
        workspace.requestCloseWorkspace { [weak self] in
            self?.appModel?.beginTerminationCleanup()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        appModel?.tearDownForTermination()
    }

    private func bringVisibleWindowsForward() {
        NSApp.activate(ignoringOtherApps: true)
        let hasActiveSheet = NSApp.windows.contains { window in
            window.isVisible && (window.isSheet || window.attachedSheet != nil)
        }
        guard !hasActiveSheet else { return }

        for window in NSApp.windows where window.canBecomeKey && window.isVisible && !window.isSheet {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
