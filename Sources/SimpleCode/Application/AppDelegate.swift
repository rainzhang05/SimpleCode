import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appModel: AppModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if ProcessInfo.processInfo.environment["SIMPLECODE_UI_TESTING"] == "1" {
            return false
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let workspace = appModel?.workspace else { return .terminateNow }
        let dirty = workspace.openDocuments.dirtySessions()
        if dirty.isEmpty {
            workspace.tearDown()
            return .terminateNow
        }
        workspace.unsavedSessionsForSheet = dirty
        workspace.pendingCloseAction = { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        appModel?.tearDownForTermination()
    }
}
