import SwiftUI
import Testing
@testable import SimpleCode

@MainActor
struct AppSettingsStoreTests {
  private func isolatedDefaults() -> UserDefaults {
    let suite = "AppSettingsStoreTests.\(UUID().uuidString)"
    return UserDefaults(suiteName: suite)!
  }

  private func persistJSONObject(_ object: [String: Any], into defaults: UserDefaults) throws {
    let data = try JSONSerialization.data(withJSONObject: object)
    defaults.set(data, forKey: AppSettingsStore.storageKey)
  }

  private func settingsJSONObject(_ mutate: (inout [String: Any]) -> Void) throws -> [String: Any] {
    let data = try JSONEncoder().encode(AppSettingsBlob.defaults)
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    mutate(&object)
    return object
  }

  @Test func defaultsOnFreshStore() {
    let store = AppSettingsStore(defaults: isolatedDefaults())
    #expect(store.typography.editorFontSize == Double(Typography.defaultEditorFontSize))
    #expect(store.editor.tabWidth == 4)
    #expect(store.files.userExclusions.isEmpty)
  }

  @Test func roundTripPersistence() {
    let defaults = isolatedDefaults()
    let store = AppSettingsStore(defaults: defaults)
    store.editor.tabWidth = 2
    store.typography.editorFontFamily = "Menlo"
    store.files.showHiddenFiles = true

    let reloaded = AppSettingsStore(defaults: defaults)
    #expect(reloaded.editor.tabWidth == 2)
    #expect(reloaded.typography.editorFontFamily == "Menlo")
    #expect(reloaded.files.showHiddenFiles)
  }

  @Test func corruptedDataFallsBackToDefaults() {
    let defaults = isolatedDefaults()
    defaults.set(Data([0xFF, 0x00, 0xAB]), forKey: AppSettingsStore.storageKey)
    let store = AppSettingsStore(defaults: defaults)
    #expect(store.editor.tabWidth == EditorBehaviorSettings.defaults.tabWidth)
  }

  @Test func missingNestedFieldKeepsOtherPersistedValues() throws {
    let defaults = isolatedDefaults()
    var object = try settingsJSONObject { object in
      var editor = object["editor"] as! [String: Any]
      editor["tabWidth"] = nil
      editor["wordWrap"] = true
      object["editor"] = editor
    }
    object["unknownFutureKey"] = ["ignored": true]
    try persistJSONObject(object, into: defaults)

    let store = AppSettingsStore(defaults: defaults)

    #expect(store.editor.tabWidth == EditorBehaviorSettings.defaults.tabWidth)
    #expect(store.editor.wordWrap)
  }

  @Test func invalidPersistedFieldsAreSanitizedIndividually() throws {
    let defaults = isolatedDefaults()
    let object = try settingsJSONObject { object in
      var editor = object["editor"] as! [String: Any]
      editor["tabWidth"] = "wide"
      editor["longLineGuideColumn"] = -50
      object["editor"] = editor

      var typography = object["typography"] as! [String: Any]
      typography["editorFontFamily"] = "DefinitelyNotARealFontFamilyXYZ"
      typography["editorFontSize"] = 500
      object["typography"] = typography

      var files = object["files"] as! [String: Any]
      files["maximumRecentWorkspaceCount"] = 999
      object["files"] = files

      var appearance = object["appearance"] as! [String: Any]
      var foreground = appearance["editorForeground"] as! [String: Any]
      var light = foreground["light"] as! [String: Any]
      light["red"] = 7
      light["green"] = -2
      foreground["light"] = light
      appearance["editorForeground"] = foreground
      object["appearance"] = appearance
    }
    try persistJSONObject(object, into: defaults)

    let store = AppSettingsStore(defaults: defaults)

    #expect(store.editor.tabWidth == EditorBehaviorSettings.defaults.tabWidth)
    #expect(store.editor.longLineGuideColumn == 40)
    #expect(store.typography.editorFontFamily == Typography.systemMonospacedFamilyName)
    #expect(store.typography.editorFontSize == Double(Typography.maximumEditorFontSize))
    #expect(store.files.maximumRecentWorkspaceCount == 50)
    #expect(store.appearance.editorForeground.light.red == 1)
    #expect(store.appearance.editorForeground.light.green == 0)
  }

  @Test func restoreSectionDefaults() {
    let store = AppSettingsStore(defaults: isolatedDefaults())
    store.editor.tabWidth = 8
    store.restoreDefaults(for: .editor)
    #expect(store.editor.tabWidth == EditorBehaviorSettings.defaults.tabWidth)
  }

  @Test func restoreAllDefaults() {
    let store = AppSettingsStore(defaults: isolatedDefaults())
    store.editor.wordWrap = true
    store.restoreAllDefaults()
    #expect(store.editor.wordWrap == false)
  }

  @Test func liveUpdateRevisionBumps() {
    let store = AppSettingsStore(defaults: isolatedDefaults())
    let before = store.revision
    store.editor.showLineNumbers.toggle()
    #expect(store.revision > before)
  }

  @Test func workspaceStateIsolation() {
    let defaults = isolatedDefaults()
    let workspaceStore = WorkspaceStateStore(defaults: defaults, storageKey: "workspaceState.test.\(UUID().uuidString)")
    let settings = AppSettingsStore(defaults: defaults)
    settings.editor.tabWidth = 2
    let id = UUID()
    workspaceStore.updateRunConfiguration(for: id) { $0.command = "echo hi" }
    #expect(workspaceStore.state(for: id).runConfiguration.command == "echo hi")
  }

  @Test func paletteReset() {
    let store = AppSettingsStore(defaults: isolatedDefaults())
    var palette = store.appearance.syntaxPalette
    palette.keyword.light.red = 0.1
    store.appearance.syntaxPalette = palette
    store.resetSyntaxPalette()
    let expected = SyntaxPaletteSettings.defaults.keyword.light.red
    #expect(abs(store.appearance.syntaxPalette.keyword.light.red - expected) < 0.02)
  }

  @Test func fontFallbackUsesSystemMonospaced() {
    let store = AppSettingsStore(defaults: isolatedDefaults())
    store.typography.editorFontFamily = "DefinitelyNotARealFontFamilyXYZ"
    let resolved = FontCatalog.resolvedMonospacedFamily(store.typography.editorFontFamily)
    #expect(resolved == Typography.systemMonospacedFamilyName)
  }
}
