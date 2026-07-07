import AppKit
import Foundation
import UniformTypeIdentifiers

/// Presents NSSavePanel for Save As. Injectable for unit tests.
@MainActor
protocol SavePanelCoordinating: AnyObject {
    func presentSavePanel(
        suggestedDirectory: URL,
        suggestedName: String,
        allowedContentTypes: [UTType]
    ) async -> URL?

    func confirmOverwrite(for url: URL) async -> Bool
}

@MainActor
final class SaveAsCoordinator: SavePanelCoordinating {
    func presentSavePanel(
        suggestedDirectory: URL,
        suggestedName: String,
        allowedContentTypes: [UTType]
    ) async -> URL? {
        let panel = NSSavePanel()
        panel.directoryURL = suggestedDirectory
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if !allowedContentTypes.isEmpty {
            panel.allowedContentTypes = allowedContentTypes
        }
        let response = await panel.begin()
        guard response == .OK, let url = panel.url else { return nil }
        return url
    }

    func confirmOverwrite(for url: URL) async -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        let alert = NSAlert()
        alert.messageText = "Replace existing file?"
        alert.informativeText = "A file named “\(url.lastPathComponent)” already exists at this location."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
