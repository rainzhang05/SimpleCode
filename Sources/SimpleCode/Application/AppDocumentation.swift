import AppKit

@MainActor
enum AppDocumentation {
    static func openBundledMarkdown(named resourceName: String) {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "md") else {
            showMissingDocumentAlert(resourceName: "\(resourceName).md")
            return
        }
        NSWorkspace.shared.open(url)
    }

    static func openBundledLicense() {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil) else {
            showMissingDocumentAlert(resourceName: "LICENSE")
            return
        }
        NSWorkspace.shared.open(url)
    }

    private static func showMissingDocumentAlert(resourceName: String) {
        let alert = NSAlert()
        alert.messageText = "SimpleCode Help"
        alert.informativeText = "The bundled document '\(resourceName)' could not be found."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
