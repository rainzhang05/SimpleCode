import AppKit
import XCTest

@MainActor
final class SimpleCodeUITests: SimpleCodeUITestCase {
    func testWelcomeLaunchesAndPrimaryActionsRemainVisible() throws {
        launchApp()
        waitForWelcome()

        XCTAssertTrue(element("welcome.recentWorkspaces").exists)
        assertWelcomeActionIsClickable(id: "welcome.action.createFolder", label: "Create a New Folder")
        assertWelcomeActionIsClickable(id: "welcome.action.openFolder", label: "Open an Existing Folder")
        assertWelcomeActionIsClickable(id: "welcome.action.cloneRepository", label: "Clone a Git Repository")
    }

    func testWelcomeRecentsAreBoundedScrollableAndClearable() throws {
        let recentRoots = try (0..<18).map { index in
            try makeTempDirectory(prefix: "SimpleCodeRecent\(index)")
        }
        let arguments = recentRoots.flatMap { ["-UITestSeedRecentWorkspace", $0.path] }

        launchApp(extraArguments: arguments)
        waitForWelcome()

        XCTAssertTrue(
            element("welcome.recentWorkspaces.scroll").waitForExistence(timeout: 2)
                || element("welcome.recentWorkspaces").exists
        )
        assertWelcomeActionIsClickable(id: "welcome.action.cloneRepository", label: "Clone a Git Repository")

        let clear = app.buttons["welcome.clearRecentWorkspaces"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clickElement(clear)
        XCTAssertTrue(app.staticTexts["No recent workspaces"].waitForExistence(timeout: 10))
    }

    func testOpenFixtureWorkspaceShowsCoreChrome() throws {
        _ = try openFixtureWorkspace()

        XCTAssertTrue(element("fileTree.sidebar").waitForExistence(timeout: 8))
        XCTAssertTrue(element("workspace.editorPlaceholder").waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["workspace.runConfigButton"].exists)
        XCTAssertTrue(app.buttons["workspace.terminalToggle"].exists)
    }

    func testWorkspaceChromeBeginsBelowToolbarAtDefaultAndResizedWindowSizes() throws {
        let fixture = try openFixtureWorkspace()
        openMainFile(in: fixture)

        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(element("settings.root").waitForExistence(timeout: 8), debugSnapshot())
        clickElement(app.buttons["Appearance"])
        clickElement(app.radioButtons["Dark"])
        assertDarkMaterial(element("settings.root").screenshot(), area: "Settings")
        app.typeKey("w", modifierFlags: .command)

        assertDarkMaterial(element("workspace.root").screenshot(), area: "workspace chrome")
        let fileTreeSidebar = element("fileTree.sidebar")
        XCTAssertTrue(fileTreeSidebar.waitForExistence(timeout: 8), debugSnapshot())
        assertDarkMaterial(fileTreeSidebar.screenshot(), area: "file tree sidebar")
        assertDarkMaterial(element("editor.textView").screenshot(), area: "editor")

        let terminalToggle = app.buttons["workspace.terminalToggle"]
        clickElement(terminalToggle)
        let terminalPanel = element("terminal.panel")
        XCTAssertTrue(terminalPanel.waitForExistence(timeout: 8), debugSnapshot())
        assertDarkMaterial(terminalPanel.screenshot(), area: "terminal")

        assertWorkspaceChromeBeginsBelowToolbar()

        let window = app.windows.firstMatch
        let originalFrame = window.frame
        app.menuBars.menuBarItems["Window"].click()
        let zoom = app.menuItems["Zoom"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 5), debugSnapshot())
        zoom.click()

        let resized = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in window.frame != originalFrame },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [resized], timeout: 5), .completed, debugSnapshot())
        assertWorkspaceChromeBeginsBelowToolbar()
    }

    func testOpenRootFileEditAndSaveUpdatesDirtyState() throws {
        let fixture = try openFixtureWorkspace()
        openMainFile(in: fixture)

        typeInEditor("\n// edited by SimpleCode UI test")

        let tab = element("editor.tab.Main.swift")
        waitForValue(tab, "modified")

        saveActiveDocument()
        waitForValue(tab, "saved", timeout: 10)

        let saved = try String(contentsOf: fixture.mainFile, encoding: .utf8)
        XCTAssertTrue(saved.contains("edited by SimpleCode UI test"))
    }

    func testEditorPaintsGlyphsForSwiftAndPlainTextFiles() throws {
        let fixture = try makeWorkspaceFixture(prefix: "SimpleCodeGlyphRendering")
        try (0..<12)
            .map { "let swiftVisualMarker\($0) = \"rendered\"" }
            .joined(separator: "\n")
            .write(to: fixture.mainFile, atomically: true, encoding: .utf8)

        let plainFile = fixture.root.appending(path: "Notes.txt")
        try (0..<12)
            .map { "plain text visual marker \($0)" }
            .joined(separator: "\n")
            .write(to: plainFile, atomically: true, encoding: .utf8)

        openWorkspace(at: fixture.root)

        let swiftRow = element("fileTree.row.Main.swift")
        XCTAssertTrue(swiftRow.waitForExistence(timeout: 8), debugSnapshot())
        clickElement(swiftRow)
        XCTAssertTrue(element("editor.tab.Main.swift").waitForExistence(timeout: 8), debugSnapshot())
        assertEditorScreenshotContainsPaintedGlyphs(fileName: "Main.swift")

        let plainRow = element("fileTree.row.Notes.txt")
        XCTAssertTrue(plainRow.waitForExistence(timeout: 8), debugSnapshot())
        clickElement(plainRow)
        XCTAssertTrue(element("editor.tab.Notes.txt").waitForExistence(timeout: 8), debugSnapshot())
        assertEditorScreenshotContainsPaintedGlyphs(fileName: "Notes.txt")
    }

    func testMarkdownSingleClickSyntaxSelectionUndoRedoAndTerminalAutofocus() throws {
        let fixture = try makeWorkspaceFixture(prefix: "SimpleCodeInteractionRegression")
        let markdown = fixture.root.appending(path: "README.md")
        try """
        # SimpleCode

        > Native macOS editor

        ```swift
        let answer = 42
        ```
        """.write(to: markdown, atomically: true, encoding: .utf8)

        openWorkspace(at: fixture.root)
        let markdownRow = element("fileTree.row.README.md")
        XCTAssertTrue(markdownRow.waitForExistence(timeout: 8), debugSnapshot())
        markdownRow.click()
        XCTAssertTrue(element("editor.tab.README.md").waitForExistence(timeout: 8), debugSnapshot())

        let editor = element("editor.textView")
        XCTAssertTrue(editor.waitForExistence(timeout: 8), debugSnapshot())
        let beforeSelection = editor.screenshot()
        editor.click()
        let afterSelection = editor.screenshot()
        assertSyntaxColorCountIsStable(before: beforeSelection, after: afterSelection)

        let originalValue = try XCTUnwrap(editor.value as? String)
        app.typeKey(.end, modifierFlags: .command)
        app.typeText("Z")
        XCTAssertEqual(editor.value as? String, originalValue + "Z")
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(editor.value as? String, originalValue)
        app.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertEqual(editor.value as? String, originalValue + "Z")
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(editor.value as? String, originalValue)
        saveActiveDocument()
        waitForValue(element("editor.tab.README.md"), "saved", timeout: 8)

        clickElement(app.buttons["workspace.terminalToggle"])
        XCTAssertTrue(element("terminal.panel").waitForExistence(timeout: 8), debugSnapshot())
        let valueBeforeTerminalTyping = editor.value as? String
        app.typeText("x")
        XCTAssertEqual(
            editor.value as? String,
            valueBeforeTerminalTyping,
            "Opening Terminal should move keyboard input out of the editor.\n\(debugSnapshot())"
        )
        clickElement(app.buttons["terminal.clearButton"])
    }

    func testPanelResizeHandlesTrackDragDistanceWithoutJumping() throws {
        let fixture = try openFixtureWorkspace()
        openMainFile(in: fixture)

        let sidebarHandle = element("fileTree.resizeHandle")
        XCTAssertTrue(sidebarHandle.waitForExistence(timeout: 8), debugSnapshot())
        let sidebarStartX = sidebarHandle.frame.midX
        sidebarHandle.click()
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertEqual(sidebarHandle.frame.midX - sidebarStartX, 16, accuracy: 2, debugSnapshot())

        clickElement(app.buttons["workspace.terminalToggle"])
        let terminalHandle = element("terminal.resizeHandle")
        XCTAssertTrue(terminalHandle.waitForExistence(timeout: 8), debugSnapshot())
        XCTAssertEqual(terminalHandle.value as? String, "220 points")
        let clearButton = app.buttons["terminal.clearButton"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5), debugSnapshot())
        XCTAssertEqual(terminalHandle.frame.width, 64, accuracy: 2, debugSnapshot())
        XCTAssertLessThan(terminalHandle.frame.maxX, clearButton.frame.minX, debugSnapshot())
    }

    func testSettingsUsesFourFocusedTabsAndConditionalEditorControls() throws {
        launchApp()
        waitForWelcome()

        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(element("settings.root").waitForExistence(timeout: 8), debugSnapshot())
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 5))

        for section in ["Appearance", "Editor", "Terminal", "Files"] {
            let tab = app.buttons[section]
            XCTAssertTrue(tab.waitForExistence(timeout: 5), debugSnapshot())
            clickElement(tab)
            XCTAssertTrue(app.windows[section].waitForExistence(timeout: 5), debugSnapshot())
        }
        XCTAssertFalse(app.buttons["Typography"].exists)

        clickElement(app.buttons["Editor"])
        XCTAssertTrue(element("settings.editor.fontFamily").exists)
        XCTAssertTrue(element("settings.editor.fontSize").exists)
        XCTAssertTrue(element("settings.editor.fontLigatures").exists)
        XCTAssertFalse(element("settings.editor.customTabWidth").exists)
        XCTAssertTrue(element("settings.editor.guideColumn").exists)

        let tabWidth = element("settings.editor.tabWidth")
        scrollToElement(tabWidth)
        clickElement(tabWidth)
        clickElement(app.menuItems["Custom"])
        let customTabWidth = element("settings.editor.customTabWidth")
        XCTAssertTrue(customTabWidth.waitForExistence(timeout: 5))
        XCTAssertEqual(customTabWidth.value as? Int, 3)
        customTabWidth.descendants(matching: .incrementArrow).firstMatch.click()
        XCTAssertEqual(customTabWidth.value as? Int, 4)
        XCTAssertTrue(customTabWidth.exists)

        clickElement(tabWidth)
        clickElement(app.menuItems["2 spaces"])
        XCTAssertFalse(customTabWidth.exists)
        clickElement(tabWidth)
        clickElement(app.menuItems["Custom"])
        XCTAssertTrue(customTabWidth.waitForExistence(timeout: 5))
        XCTAssertEqual(customTabWidth.value as? Int, 4)

        let whitespace = element("settings.editor.showWhitespace")
        let trailingWhitespace = element("settings.editor.showTrailingWhitespace")
        XCTAssertEqual(whitespace.value as? Int, 0)
        XCTAssertEqual(trailingWhitespace.value as? Int, 0)
        clickSwitch(whitespace)
        XCTAssertEqual(whitespace.value as? Int, 1)
        XCTAssertEqual(trailingWhitespace.value as? Int, 0)

        clickSwitch(element("settings.editor.longLineGuide"))
        XCTAssertFalse(element("settings.editor.guideColumn").exists)
        clickSwitch(element("settings.editor.longLineGuide"))
        XCTAssertTrue(element("settings.editor.guideColumn").waitForExistence(timeout: 5))

        clickElement(app.buttons["Terminal"])
        XCTAssertTrue(element("settings.terminal.fontFamily").exists)
        XCTAssertTrue(element("settings.terminal.fontSize").exists)

        clickElement(app.buttons["Appearance"])
        XCTAssertTrue(app.windows["Appearance"].waitForExistence(timeout: 5), debugSnapshot())
        let dark = app.radioButtons["Dark"]
        XCTAssertTrue(dark.waitForExistence(timeout: 5), debugSnapshot())
        clickElement(dark)
        assertDarkMaterial(element("settings.root").screenshot(), area: "Settings")
    }

    func testFindReplaceOneOccurrence() throws {
        let fixture = try openFixtureWorkspace()
        openMainFile(in: fixture)

        app.typeKey("f", modifierFlags: [.command, .option])
        let searchField = app.textFields["find.searchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), debugSnapshot())
        focusTextField(searchField)
        typeInField(searchField, text: "greeting")

        let replaceField = app.textFields["find.replaceField"]
        XCTAssertTrue(replaceField.waitForExistence(timeout: 5), debugSnapshot())
        typeInField(replaceField, text: "message")

        app.buttons["find.next"].click()
        app.buttons["find.replace"].click()
        XCTAssertTrue(app.buttons["find.close"].waitForExistence(timeout: 5))
        app.buttons["find.close"].click()

        saveActiveDocument()
        waitForValue(element("editor.tab.Main.swift"), "saved", timeout: 10)

        let saved = try String(contentsOf: fixture.mainFile, encoding: .utf8)
        XCTAssertTrue(saved.contains("message"))
    }

    func testTerminalPanelTogglesOnce() throws {
        _ = try openFixtureWorkspace()

        let toggle = app.buttons["workspace.terminalToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.click()
        XCTAssertTrue(element("terminal.panel").waitForExistence(timeout: 8), debugSnapshot())
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "terminal.panel").count, 1)

        toggle.click()
        XCTAssertFalse(element("terminal.panel").waitForExistence(timeout: 2))
    }

    func testTerminalPanelActionsAreCompactAndCentered() throws {
        _ = try openFixtureWorkspace()

        let toggle = app.buttons["workspace.terminalToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.click()

        let panel = element("terminal.panel")
        let clear = app.buttons["terminal.clearButton"]
        let close = app.buttons["terminal.closeButton"]
        XCTAssertTrue(panel.waitForExistence(timeout: 8), debugSnapshot())
        XCTAssertTrue(clear.waitForExistence(timeout: 5), debugSnapshot())
        XCTAssertTrue(close.waitForExistence(timeout: 5), debugSnapshot())

        for action in [clear, close] {
            XCTAssertEqual(action.frame.width, 24, accuracy: 0.5)
            XCTAssertEqual(action.frame.height, 24, accuracy: 0.5)
            XCTAssertTrue(action.isHittable)
            XCTAssertEqual(action.frame.midY, panel.frame.minY + 26, accuracy: 1)
        }
        XCTAssertEqual(clear.frame.midY, close.frame.midY, accuracy: 0.5)
    }

    func testCloneSheetValidatesInvalidInputWithoutNetwork() throws {
        let parent = try makeTempDirectory(prefix: "SimpleCodeCloneDestination")
        openCloneSheet(extraArguments: ["-UITestCloneDestination", parent.path])

        app.typeText("not-a-url")
        app.typeKey(.return, modifierFlags: [])
        waitForModalSheet(timeout: 2)

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("welcome.root").waitForExistence(timeout: 5), debugSnapshot())
    }

    func testDirtyCloseCancelThenDontSaveReturnsToWelcome() throws {
        let fixture = try openFixtureWorkspace()
        openMainFile(in: fixture)

        typeInEditor("\n// dirty close test")
        waitForValue(element("editor.tab.Main.swift"), "modified")

        app.typeKey("w", modifierFlags: [.command, .shift])
        let cancel = app.buttons["unsaved.sheet.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 8), debugSnapshot())
        cancel.click()
        XCTAssertTrue(element("workspace.root").waitForExistence(timeout: 5))

        app.typeKey("w", modifierFlags: [.command, .shift])
        let dontSave = app.buttons["unsaved.sheet.dontSave"]
        XCTAssertTrue(dontSave.waitForExistence(timeout: 8), debugSnapshot())
        dontSave.click()
        waitForWelcome()
    }

    private func assertEditorScreenshotContainsPaintedGlyphs(
        fileName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let editor = element("editor.textView")
        XCTAssertTrue(editor.waitForExistence(timeout: 8), debugSnapshot(), file: file, line: line)

        let screenshot = editor.screenshot()
        guard let tiff = screenshot.image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              bitmap.pixelsWide > 80,
              bitmap.pixelsHigh > 100 else {
            XCTFail("Could not inspect the rendered editor screenshot for \(fileName).", file: file, line: line)
            return
        }

        let sampleX = max(0, bitmap.pixelsWide - 16)
        let sampleY = bitmap.pixelsHigh / 2
        guard let background = rgb(bitmap.colorAt(x: sampleX, y: sampleY)) else {
            XCTFail("Could not read the editor background pixels for \(fileName).", file: file, line: line)
            return
        }

        // Exclude the line-number gutter: this assertion must prove source glyphs
        // are painted, not merely that the gutter labels are visible.
        let xRange = 72..<min(bitmap.pixelsWide - 16, 320)
        let yRange = 40..<max(41, bitmap.pixelsHigh - 40)
        var inkPixels = 0
        var rowsWithInk = 0
        var maximumDistance: CGFloat = 0

        for y in yRange {
            var inkInRow = 0
            for x in xRange {
                guard let color = rgb(bitmap.colorAt(x: x, y: y)) else { continue }
                let distance = abs(color.red - background.red)
                    + abs(color.green - background.green)
                    + abs(color.blue - background.blue)
                maximumDistance = max(maximumDistance, distance)
                if distance > 0.18 {
                    inkInRow += 1
                }
            }
            inkPixels += inkInRow
            if inkInRow >= 3 {
                rowsWithInk += 1
            }
        }

        if inkPixels <= 80 {
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "Editor rendering - \(fileName)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        XCTAssertGreaterThan(
            inkPixels,
            80,
            "Expected painted glyph pixels for \(fileName), not only accessibility text (\(bitmap.pixelsWide)x\(bitmap.pixelsHigh), max color distance \(maximumDistance)).\n\(debugSnapshot())",
            file: file,
            line: line
        )
        XCTAssertGreaterThan(
            rowsWithInk,
            4,
            "Expected glyph-shaped ink across several rows for \(fileName).",
            file: file,
            line: line
        )

        assertLineNumberGutterContainsLabels(
            bitmap,
            fileName: fileName,
            file: file,
            line: line
        )
    }

    private func assertDarkMaterial(
        _ screenshot: XCUIScreenshot,
        area: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let tiff = screenshot.image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              bitmap.pixelsWide > 32,
              bitmap.pixelsHigh > 32 else {
            XCTFail("Could not inspect dark rendering for \(area).", file: file, line: line)
            return
        }

        var darkSamples = 0
        var samples = 0
        var totalLuminance: CGFloat = 0
        for y in stride(from: 8, to: bitmap.pixelsHigh, by: 12) {
            for x in stride(from: 8, to: bitmap.pixelsWide, by: 12) {
                guard let color = rgb(bitmap.colorAt(x: x, y: y)) else { continue }
                let luminance = 0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue
                samples += 1
                totalLuminance += luminance
                if luminance < 0.5 { darkSamples += 1 }
            }
        }

        let darkFraction = samples == 0 ? 0 : CGFloat(darkSamples) / CGFloat(samples)
        let meanLuminance = samples == 0 ? 1 : totalLuminance / CGFloat(samples)
        if samples < 100 || darkFraction <= 0.65 || meanLuminance >= 0.42 {
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "Dark rendering - \(area)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertGreaterThanOrEqual(samples, 100, "Expected enough pixels to inspect \(area).", file: file, line: line)
        XCTAssertGreaterThan(
            darkFraction,
            0.65,
            "Expected \(area) to be predominantly dark; dark fraction was \(darkFraction).",
            file: file,
            line: line
        )
        XCTAssertLessThan(
            meanLuminance,
            0.42,
            "Expected low average luminance for \(area); mean was \(meanLuminance).",
            file: file,
            line: line
        )
    }

    private func assertSyntaxColorCountIsStable(
        before: XCUIScreenshot,
        after: XCUIScreenshot,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let beforeCount = syntaxColoredPixelCount(in: before)
        let afterCount = syntaxColoredPixelCount(in: after)
        XCTAssertGreaterThan(beforeCount, 20, "Expected visible syntax colors before selection.", file: file, line: line)
        XCTAssertGreaterThan(
            afterCount,
            beforeCount * 3 / 4,
            "Selection removed syntax colors: before=\(beforeCount), after=\(afterCount).",
            file: file,
            line: line
        )
    }

    private func syntaxColoredPixelCount(in screenshot: XCUIScreenshot) -> Int {
        guard let data = screenshot.image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data) else { return 0 }
        var count = 0
        for y in stride(from: 2, to: bitmap.pixelsHigh, by: 2) {
            for x in stride(from: 2, to: bitmap.pixelsWide, by: 2) {
                guard let color = rgb(bitmap.colorAt(x: x, y: y)) else { continue }
                let spread = max(color.red, color.green, color.blue) - min(color.red, color.green, color.blue)
                if spread > 0.16, min(color.red, color.green, color.blue) < 0.9 {
                    count += 1
                }
            }
        }
        return count
    }

    private func clickSwitch(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), debugSnapshot())
        scrollToElement(element)
        element.click()
    }

    private func scrollToElement(_ element: XCUIElement) {
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<6 where !element.isHittable {
            scrollView.swipeUp()
        }
        XCTAssertTrue(element.isHittable, debugSnapshot())
    }

    private func assertWorkspaceChromeBeginsBelowToolbar(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let toolbar = app.toolbars.firstMatch
        let filesHeader = app.staticTexts["Files"]
        let editorTab = element("editor.tab.Main.swift")

        XCTAssertTrue(toolbar.waitForExistence(timeout: 5), debugSnapshot(), file: file, line: line)
        XCTAssertTrue(filesHeader.waitForExistence(timeout: 5), debugSnapshot(), file: file, line: line)
        XCTAssertTrue(editorTab.waitForExistence(timeout: 5), debugSnapshot(), file: file, line: line)
        let frames = [
            ("native toolbar", toolbar.frame),
            ("Files header", filesHeader.frame),
            ("editor tab", editorTab.frame)
        ]
        for (name, frame) in frames {
            XCTAssertFalse(frame.isNull, "Expected a valid frame for \(name).", file: file, line: line)
            XCTAssertFalse(frame.isInfinite, "Expected a finite frame for \(name).", file: file, line: line)
            XCTAssertGreaterThan(frame.width, 0, "Expected positive width for \(name).", file: file, line: line)
            XCTAssertGreaterThan(frame.height, 0, "Expected positive height for \(name).", file: file, line: line)
        }
        let toolbarBottom = toolbar.frame.maxY
        XCTAssertGreaterThanOrEqual(
            filesHeader.frame.minY,
            toolbarBottom,
            "Files header overlaps the native toolbar.\n\(debugSnapshot())",
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            editorTab.frame.minY,
            toolbarBottom,
            "Editor tab overlaps the native toolbar.\n\(debugSnapshot())",
            file: file,
            line: line
        )
    }

    private func assertLineNumberGutterContainsLabels(
        _ bitmap: NSBitmapImageRep,
        fileName: String,
        file: StaticString,
        line: UInt
    ) {
        // Sample a quiet part of the gutter, then look for the line-number glyphs
        // above it. This verifies the TextKit 2 gutter itself rather than only the
        // source text rendered beside it.
        guard let background = rgb(bitmap.colorAt(x: 8, y: bitmap.pixelsHigh / 2)) else {
            XCTFail("Could not read the line-number gutter background for \(fileName).", file: file, line: line)
            return
        }

        let xRange = 12..<min(80, bitmap.pixelsWide)
        let yRange = 12..<min(340, bitmap.pixelsHigh - 12)
        var labelPixels = 0
        for y in yRange {
            for x in xRange {
                guard let color = rgb(bitmap.colorAt(x: x, y: y)) else { continue }
                let distance = abs(color.red - background.red)
                    + abs(color.green - background.green)
                    + abs(color.blue - background.blue)
                if distance > 0.08 {
                    labelPixels += 1
                }
            }
        }

        XCTAssertGreaterThan(
            labelPixels,
            15,
            "Expected visible line-number labels for \(fileName), not only a gutter background.",
            file: file,
            line: line
        )
    }

    private func rgb(_ color: NSColor?) -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        guard let color = color?.usingColorSpace(.deviceRGB) else { return nil }
        return (color.redComponent, color.greenComponent, color.blueComponent)
    }
}
