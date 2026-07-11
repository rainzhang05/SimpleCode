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

  private func colorPair(
    light: (Double, Double, Double, Double),
    dark: (Double, Double, Double, Double)
  ) -> [String: Any] {
    [
      "light": ["red": light.0, "green": light.1, "blue": light.2, "alpha": light.3],
      "dark": ["red": dark.0, "green": dark.1, "blue": dark.2, "alpha": dark.3],
    ]
  }

  private var v1EditorBackground: [String: Any] {
    colorPair(light: (0.99, 0.99, 0.99, 1), dark: (0.11, 0.11, 0.12, 1))
  }

  private var v1GutterBackground: [String: Any] {
    colorPair(light: (0.97, 0.97, 0.97, 1), dark: (0.09, 0.09, 0.10, 1))
  }

  private var v1TerminalBackground: [String: Any] {
    colorPair(light: (0.98, 0.98, 0.98, 1), dark: (0.08, 0.08, 0.09, 1))
  }

  private var v1TerminalForeground: [String: Any] {
    colorPair(light: (0.10, 0.10, 0.10, 1), dark: (0.90, 0.90, 0.90, 1))
  }

  @Test func defaultsOnFreshStore() {
    let store = AppSettingsStore(defaults: isolatedDefaults())
    #expect(store.typography.editorFontSize == Double(Typography.defaultEditorFontSize))
    #expect(store.editor.tabWidth == 4)
    #expect(store.files.userExclusions.isEmpty)
    #expect(store.files.showHiddenFiles)
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

  @Test func schemaVersionOneMigratesDefaultPaletteAndAlwaysShowsDotfiles() throws {
    let defaults = isolatedDefaults()
    let object = try settingsJSONObject { object in
      object["schemaVersion"] = 1
      var appearance = object["appearance"] as! [String: Any]
      appearance["editorBackground"] = v1EditorBackground
      appearance["gutterBackground"] = v1GutterBackground
      appearance["terminalBackground"] = v1TerminalBackground
      appearance["terminalForeground"] = v1TerminalForeground
      object["appearance"] = appearance

      var files = object["files"] as! [String: Any]
      files["showHiddenFiles"] = false
      object["files"] = files
    }
    try persistJSONObject(object, into: defaults)

    let store = AppSettingsStore(defaults: defaults)

    #expect(store.appearance.editorBackground == AppearanceSettings.defaults.editorBackground)
    #expect(store.appearance.gutterBackground == AppearanceSettings.defaults.gutterBackground)
    #expect(store.appearance.terminalBackground == AppearanceSettings.defaults.terminalBackground)
    #expect(store.appearance.terminalForeground == AppearanceSettings.defaults.terminalForeground)
    #expect(store.files.showHiddenFiles)

    store.editor.tabWidth = 2
    let persisted = try #require(defaults.data(forKey: AppSettingsStore.storageKey))
    let persistedObject = try #require(JSONSerialization.jsonObject(with: persisted) as? [String: Any])
    #expect(persistedObject["schemaVersion"] as? Int == AppSettingsBlob.currentSchemaVersion)
  }

  @Test func schemaVersionOnePreservesCustomAppearanceColors() throws {
    let defaults = isolatedDefaults()
    let customBackground = colorPair(light: (0.21, 0.13, 0.37, 1), dark: (0.10, 0.04, 0.19, 1))
    let object = try settingsJSONObject { object in
      object["schemaVersion"] = 1
      var appearance = object["appearance"] as! [String: Any]
      appearance["terminalBackground"] = customBackground
      object["appearance"] = appearance
    }
    try persistJSONObject(object, into: defaults)

    let store = AppSettingsStore(defaults: defaults)

    #expect(store.appearance.terminalBackground.light.red == 0.21)
    #expect(store.appearance.terminalBackground.dark.blue == 0.19)
  }

  @Test func schemaVersionOneUsesLegacyTerminalValuesWhenModernCounterpartsAreDefaults() throws {
    let defaults = isolatedDefaults()
    let legacyBackground = colorPair(light: (0.21, 0.13, 0.37, 1), dark: (0.10, 0.04, 0.19, 1))
    let legacyForeground = colorPair(light: (0.97, 0.86, 1.0, 1), dark: (0.91, 0.78, 1.0, 1))
    let object = try settingsJSONObject { object in
      object["schemaVersion"] = 1
      var appearance = object["appearance"] as! [String: Any]
      appearance["terminalBackground"] = v1TerminalBackground
      appearance["terminalForeground"] = v1TerminalForeground
      object["appearance"] = appearance

      var terminal = object["terminal"] as! [String: Any]
      terminal["fontFamily"] = "Menlo"
      terminal["fontSize"] = 17
      terminal["background"] = legacyBackground
      terminal["foreground"] = legacyForeground
      object["terminal"] = terminal
    }
    try persistJSONObject(object, into: defaults)

    let store = AppSettingsStore(defaults: defaults)

    #expect(store.typography.terminalFontFamily == "Menlo")
    #expect(store.typography.terminalFontSize == 17)
    #expect(store.appearance.terminalBackground.light.red == 0.21)
    #expect(store.appearance.terminalForeground.dark.green == 0.78)
  }

  @Test func schemaVersionOneKeepsExplicitModernTerminalValues() throws {
    let defaults = isolatedDefaults()
    let modernBackground = colorPair(light: (0.34, 0.15, 0.52, 1), dark: (0.16, 0.07, 0.26, 1))
    let legacyBackground = colorPair(light: (0.21, 0.13, 0.37, 1), dark: (0.10, 0.04, 0.19, 1))
    let object = try settingsJSONObject { object in
      object["schemaVersion"] = 1
      var typography = object["typography"] as! [String: Any]
      typography["terminalFontFamily"] = "Monaco"
      typography["terminalFontSize"] = 15
      object["typography"] = typography

      var appearance = object["appearance"] as! [String: Any]
      appearance["terminalBackground"] = modernBackground
      object["appearance"] = appearance

      var terminal = object["terminal"] as! [String: Any]
      terminal["fontFamily"] = "Menlo"
      terminal["fontSize"] = 17
      terminal["background"] = legacyBackground
      object["terminal"] = terminal
    }
    try persistJSONObject(object, into: defaults)

    let store = AppSettingsStore(defaults: defaults)

    #expect(store.typography.terminalFontFamily == "Monaco")
    #expect(store.typography.terminalFontSize == 15)
    #expect(store.appearance.terminalBackground.light.red == 0.34)
  }

  @Test func legacyFontSizeDoesNotOverrideAPersistedSettingsBlob() throws {
    let defaults = isolatedDefaults()
    defaults.set(18, forKey: "editor.fontSize.v1")
    let object = try settingsJSONObject { object in
      var typography = object["typography"] as! [String: Any]
      typography["editorFontSize"] = 15
      object["typography"] = typography
    }
    try persistJSONObject(object, into: defaults)

    let store = AppSettingsStore(defaults: defaults)

    #expect(store.typography.editorFontSize == 15)
  }

  @Test func aFutureSchemaIsNeverDowngradedOrOverwritten() throws {
    let defaults = isolatedDefaults()
    let object = try settingsJSONObject { object in
      object["schemaVersion"] = AppSettingsBlob.currentSchemaVersion + 1
      var editor = object["editor"] as! [String: Any]
      editor["tabWidth"] = 3
      object["editor"] = editor
    }
    try persistJSONObject(object, into: defaults)
    let originalData = try #require(defaults.data(forKey: AppSettingsStore.storageKey))

    let store = AppSettingsStore(defaults: defaults)
    store.editor.tabWidth = 2

    #expect(defaults.data(forKey: AppSettingsStore.storageKey) == originalData)
  }
}
