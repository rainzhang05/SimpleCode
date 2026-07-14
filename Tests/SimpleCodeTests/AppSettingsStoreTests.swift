import AppKit
import Testing
@testable import SimpleCode

private final class CountingSettingsUserDefaults: UserDefaults {
  private var storage: [String: Any] = [:]
  private(set) var settingsWriteCount = 0

  init() {
    super.init(suiteName: "CountingSettingsUserDefaults.\(UUID().uuidString)")!
  }

  override func data(forKey defaultName: String) -> Data? {
    storage[defaultName] as? Data
  }

  override func double(forKey defaultName: String) -> Double {
    (storage[defaultName] as? NSNumber)?.doubleValue ?? 0
  }

  override func set(_ value: Any?, forKey defaultName: String) {
    storage[defaultName] = value
    if defaultName == "com.simplecode.settings.v1" {
      settingsWriteCount += 1
    }
  }
}

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
    #expect(AppSettingsBlob.currentSchemaVersion == 4)
    #expect(store.typography.editorFontSize == Double(Typography.defaultEditorFontSize))
    #expect(store.editor.tabWidth == 4)
    #expect(store.files.userExclusions.isEmpty)
  }

  @Test func roundTripPersistence() {
    let defaults = isolatedDefaults()
    let store = AppSettingsStore(defaults: defaults)
    store.editor.tabWidth = 2
    store.typography.editorFontFamily = "Menlo"
    store.files.userExclusions = [".build"]
    store.appearance.mode = .dark

    let reloaded = AppSettingsStore(defaults: defaults)
    #expect(reloaded.editor.tabWidth == 2)
    #expect(reloaded.typography.editorFontFamily == "Menlo")
    #expect(reloaded.files.userExclusions == [".build"])
    #expect(reloaded.appearance.mode == .dark)
  }

  @Test func appearanceModeAppliesToApplication() {
    let previousAppearance = NSApp.appearance
    defer { NSApp.appearance = previousAppearance }
    NSApp.appearance = nil
    let store = AppSettingsStore(defaults: isolatedDefaults())

    store.appearance.mode = .light
    #expect(NSApp.appearance?.name == .aqua)

    store.appearance.mode = .dark
    #expect(NSApp.appearance?.name == .darkAqua)

    store.appearance.mode = .system
    #expect(NSApp.appearance == nil)
  }

  @Test func snapshotIsImmutableAndTracksLiveSettings() {
    let store = AppSettingsStore(defaults: isolatedDefaults())
    let original = store.snapshot

    store.editor.tabWidth = 2
    store.files.userExclusions = ["DerivedData"]
    let updated = store.snapshot

    #expect(original == .defaults)
    #expect(original.editor.tabWidth == 4)
    #expect(updated.editor.tabWidth == 2)
    #expect(updated.files.userExclusions == ["DerivedData"])
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

    }
    try persistJSONObject(object, into: defaults)

    let store = AppSettingsStore(defaults: defaults)

    #expect(store.editor.tabWidth == EditorBehaviorSettings.defaults.tabWidth)
    #expect(store.editor.longLineGuideColumn == 40)
    #expect(store.typography.editorFontFamily == Typography.systemMonospacedFamilyName)
    #expect(store.typography.editorFontSize == Double(Typography.maximumEditorFontSize))
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

  @Test func restoreAllDefaultsPersistsExactlyOnce() {
    let defaults = CountingSettingsUserDefaults()
    let store = AppSettingsStore(defaults: defaults)
    store.editor.wordWrap = true
    let writesBeforeReset = defaults.settingsWriteCount

    store.restoreAllDefaults()

    #expect(defaults.settingsWriteCount == writesBeforeReset + 1)
    #expect(AppSettingsStore(defaults: defaults).editor == EditorBehaviorSettings.defaults)
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

  @Test func fontFallbackUsesSystemMonospaced() {
    let store = AppSettingsStore(defaults: isolatedDefaults())
    store.typography.editorFontFamily = "DefinitelyNotARealFontFamilyXYZ"
    let resolved = FontCatalog.resolvedMonospacedFamily(store.typography.editorFontFamily)
    #expect(resolved == Typography.systemMonospacedFamilyName)
  }

  @Test func schemaVersionOneUsesLegacyTerminalTypographyWhenModernCounterpartsAreDefaults() throws {
    let defaults = isolatedDefaults()
    let object = try settingsJSONObject { object in
      object["schemaVersion"] = 1
      var terminal: [String: Any] = [:]
      terminal["fontFamily"] = "Menlo"
      terminal["fontSize"] = 17
      object["terminal"] = terminal
    }
    try persistJSONObject(object, into: defaults)

    let store = AppSettingsStore(defaults: defaults)

    #expect(store.typography.terminalFontFamily == "Menlo")
    #expect(store.typography.terminalFontSize == 17)
  }

  @Test func schemaVersionOneKeepsExplicitModernTerminalTypography() throws {
    let defaults = isolatedDefaults()
    let object = try settingsJSONObject { object in
      object["schemaVersion"] = 1
      var typography = object["typography"] as! [String: Any]
      typography["terminalFontFamily"] = "Monaco"
      typography["terminalFontSize"] = 15
      object["typography"] = typography

      var terminal: [String: Any] = [:]
      terminal["fontFamily"] = "Menlo"
      terminal["fontSize"] = 17
      object["terminal"] = terminal
    }
    try persistJSONObject(object, into: defaults)

    let store = AppSettingsStore(defaults: defaults)

    #expect(store.typography.terminalFontFamily == "Monaco")
    #expect(store.typography.terminalFontSize == 15)
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

  @Test func tabWidthChoicesHaveUniqueTagsAndStableCustomSelection() {
    #expect(Set(EditorTabWidthChoice.options).count == EditorTabWidthChoice.options.count)
    #expect(EditorTabWidthChoice.selection(for: 2) == .preset(2))
    #expect(EditorTabWidthChoice.selection(for: 3) == .custom)
    #expect(EditorTabWidthChoice.custom.width == EditorTabWidthChoice.defaultCustomWidth)
  }

  @Test func fileTreeRefreshDecisionOnlyRespondsToExclusionChanges() {
    let original = AppSettingsSnapshot.defaults

    let appearanceChange = AppSettingsSnapshot(
      appearance: AppearanceSettings(mode: .dark),
      typography: original.typography,
      editor: original.editor,
      files: original.files
    )

    var typography = original.typography
    typography.editorFontSize += 1
    let typographyChange = AppSettingsSnapshot(
      appearance: original.appearance,
      typography: typography,
      editor: original.editor,
      files: original.files
    )

    var editor = original.editor
    editor.wordWrap.toggle()
    let editorChange = AppSettingsSnapshot(
      appearance: original.appearance,
      typography: original.typography,
      editor: editor,
      files: original.files
    )

    let exclusionChange = AppSettingsSnapshot(
      appearance: original.appearance,
      typography: original.typography,
      editor: original.editor,
      files: FileDisplaySettings(userExclusions: ["DerivedData"])
    )

    #expect(!FileTreeSettingsRefreshPolicy.shouldRefresh(from: original, to: appearanceChange))
    #expect(!FileTreeSettingsRefreshPolicy.shouldRefresh(from: original, to: typographyChange))
    #expect(!FileTreeSettingsRefreshPolicy.shouldRefresh(from: original, to: editorChange))
    #expect(FileTreeSettingsRefreshPolicy.shouldRefresh(from: original, to: exclusionChange))
  }

  @Test func schemaVersionThreeDoesNotPersistRemovedBackingFields() throws {
    let encoded = try JSONEncoder().encode(AppSettingsBlob.defaults)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let typography = try #require(object["typography"] as? [String: Any])
    let editor = try #require(object["editor"] as? [String: Any])
    let files = try #require(object["files"] as? [String: Any])

    #expect(object["terminal"] == nil)
    #expect(typography["terminalLineSpacing"] == nil)
    #expect(editor["automaticSyntaxHighlighting"] == nil)
    #expect(editor["restoreOpenEditors"] == nil)
    #expect(files["showHiddenFiles"] == nil)
    #expect(files["confirmBeforeTrash"] == nil)
    #expect(files["defaultEncoding"] == nil)
    #expect(files["defaultLineEnding"] == nil)
    #expect(files["confirmBeforeOpeningLargeFiles"] == nil)
    #expect(files["restoreRecentWorkspaces"] == nil)
    #expect(files["maximumRecentWorkspaceCount"] == nil)
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

  @Test func aFutureSchemaWithUnknownAppearanceModeIsNeverOverwritten() throws {
    let defaults = isolatedDefaults()
    let object = try settingsJSONObject { object in
      object["schemaVersion"] = AppSettingsBlob.currentSchemaVersion + 1
      var appearance = object["appearance"] as! [String: Any]
      appearance["mode"] = "highContrast"
      object["appearance"] = appearance
    }
    try persistJSONObject(object, into: defaults)
    let originalData = try #require(defaults.data(forKey: AppSettingsStore.storageKey))

    let store = AppSettingsStore(defaults: defaults)
    store.editor.tabWidth = 2

    #expect(defaults.data(forKey: AppSettingsStore.storageKey) == originalData)
  }

  @Test func persistedAppearanceModeIsAppliedDuringInitialization() throws {
    let previousAppearance = NSApp.appearance
    defer { NSApp.appearance = previousAppearance }
    let defaults = isolatedDefaults()
    let object = try settingsJSONObject { object in
      var appearance = object["appearance"] as! [String: Any]
      appearance["mode"] = "dark"
      object["appearance"] = appearance
    }
    try persistJSONObject(object, into: defaults)
    NSApp.appearance = nil

    _ = AppSettingsStore(defaults: defaults)

    #expect(NSApp.appearance?.name == .darkAqua)
  }

  @Test func schemaVersionFourPersistsOnlyAppearanceModeAndFunctionalTypography() throws {
    let encoded = try JSONEncoder().encode(AppSettingsBlob.defaults)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let appearance = try #require(object["appearance"] as? [String: Any])
    let typography = try #require(object["typography"] as? [String: Any])

    #expect(AppSettingsBlob.currentSchemaVersion == 4)
    #expect(appearance.keys.sorted() == ["mode"])
    #expect(appearance["mode"] as? String == "system")
    #expect(typography["editorLineHeight"] == nil)
  }

  @Test func schemaVersionsOneThroughThreePreserveFunctionalValuesAndDropLegacyAppearance() throws {
    for schemaVersion in 1...3 {
      let defaults = isolatedDefaults()
      let object = try settingsJSONObject { object in
        object["schemaVersion"] = schemaVersion

        var appearance = object["appearance"] as! [String: Any]
        appearance["editorBackground"] = [
          "light": ["red": 0.21, "green": 0.13, "blue": 0.37, "alpha": 0.4],
          "dark": ["red": 0.10, "green": 0.04, "blue": 0.19, "alpha": 0.7],
        ]
        object["appearance"] = appearance

        var typography = object["typography"] as! [String: Any]
        typography["editorFontFamily"] = "Menlo"
        typography["editorFontSize"] = 15
        typography["editorLineHeight"] = 2.25
        typography["terminalFontFamily"] = "Monaco"
        typography["terminalFontSize"] = 17
        object["typography"] = typography

        var editor = object["editor"] as! [String: Any]
        editor["tabWidth"] = 2
        editor["wordWrap"] = true
        object["editor"] = editor

        var files = object["files"] as! [String: Any]
        files["userExclusions"] = ["DerivedData", ".build"]
        object["files"] = files
      }
      try persistJSONObject(object, into: defaults)

      let store = AppSettingsStore(defaults: defaults)
      #expect(store.typography.editorFontFamily == "Menlo")
      #expect(store.typography.editorFontSize == 15)
      #expect(store.typography.terminalFontFamily == "Monaco")
      #expect(store.typography.terminalFontSize == 17)
      #expect(store.editor.tabWidth == 2)
      #expect(store.editor.wordWrap)
      #expect(store.files.userExclusions == ["DerivedData", ".build"])

      store.editor.autoIndent.toggle()
      let persisted = try #require(defaults.data(forKey: AppSettingsStore.storageKey))
      let migrated = try #require(JSONSerialization.jsonObject(with: persisted) as? [String: Any])
      let appearance = try #require(migrated["appearance"] as? [String: Any])
      let migratedTypography = try #require(migrated["typography"] as? [String: Any])
      #expect(migrated["schemaVersion"] as? Int == 4)
      #expect(appearance.keys.sorted() == ["mode"])
      #expect(appearance["mode"] as? String == "system")
      #expect(migratedTypography["editorLineHeight"] == nil)
    }
  }
}
