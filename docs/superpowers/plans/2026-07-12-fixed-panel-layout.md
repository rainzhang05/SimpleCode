# Fixed Panel Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent the file sidebar from covering code and replace the sidebar and terminal scale/fade effects with constant-size, offset-only sliding.

**Architecture:** Keep the existing layered workspace so AppKit editor and terminal views remain mounted. Add pure geometry helpers to `WorkspacePanelLayout`, use them to reserve the sidebar lane inside the editor, and drive full-distance panel offsets without opacity, scaling, or terminal-dependent sidebar sizing.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, Xcode macOS scheme

## Global Constraints

- Work directly on `main`; do not create another branch or worktree.
- Use small commits with short subjects, no bodies, and no coauthor trailers.
- Keep liquid-glass panel styling and configured panel dimensions unchanged.
- Use test-first red-green cycles for each behavior change.
- Push `main` only after the full unit suite and macOS build pass.

---

### Task 1: Reserve editor space for the sidebar

**Files:**
- Modify: `Sources/SimpleCode/Features/Workspace/WorkspaceModel.swift`
- Modify: `Sources/SimpleCode/Features/Workspace/WorkspaceView.swift`
- Test: `Tests/SimpleCodeTests/AppModelTests.swift`

**Interfaces:**
- Produces: `WorkspacePanelLayout.sidebarReservation(sidebarWidth:panelInset:isVisible:) -> CGFloat`
- Consumes: `workspace.sidebarWidth`, `workspace.isSidebarVisible`, and `Spacing.small`

- [ ] **Step 1: Write the failing geometry test**

Add assertions proving that a visible 280-point sidebar with 12-point outer insets reserves 304 points and a hidden sidebar reserves zero.

```swift
@Test func workspacePanelLayoutReservesEditorSpaceForVisibleSidebar() {
    #expect(WorkspacePanelLayout.sidebarReservation(
        sidebarWidth: 280,
        panelInset: 12,
        isVisible: true
    ) == 304)
    #expect(WorkspacePanelLayout.sidebarReservation(
        sidebarWidth: 280,
        panelInset: 12,
        isVisible: false
    ) == 0)
}
```

- [ ] **Step 2: Verify the test fails**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -quiet -project SimpleCode.xcodeproj -scheme SimpleCode -destination 'platform=macOS' -only-testing:SimpleCodeTests/AppModelTests
```

Expected: compilation fails because `sidebarReservation` does not exist.

- [ ] **Step 3: Implement the helper and editor reservation**

Add the pure helper:

```swift
static func sidebarReservation(
    sidebarWidth: CGFloat,
    panelInset: CGFloat,
    isVisible: Bool
) -> CGFloat {
    guard isVisible else { return 0 }
    return clampedSidebarWidth(sidebarWidth) + max(0, panelInset) * 2
}
```

In `workspaceLayers`, apply the returned value as leading padding inside the editor's full workspace frame. Animate only changes to `isSidebarVisible`, and disable that animation under Reduce Motion.

- [ ] **Step 4: Verify the focused test and build**

Run the focused test command from Step 2, followed by:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild build -quiet -project SimpleCode.xcodeproj -scheme SimpleCode -destination 'platform=macOS'
```

Expected: both commands exit 0.

- [ ] **Step 5: Commit**

```bash
git add Sources/SimpleCode/Features/Workspace/WorkspaceModel.swift Sources/SimpleCode/Features/Workspace/WorkspaceView.swift Tests/SimpleCodeTests/AppModelTests.swift
git commit -m "fix: reserve space for sidebar"
```

### Task 2: Use fixed-size offset-only panel motion

**Files:**
- Modify: `Sources/SimpleCode/Features/Workspace/WorkspaceModel.swift`
- Modify: `Sources/SimpleCode/Features/Workspace/WorkspaceView.swift`
- Test: `Tests/SimpleCodeTests/AppModelTests.swift`

**Interfaces:**
- Produces: `WorkspacePanelLayout.sidebarOffset(sidebarWidth:panelInset:isVisible:) -> CGFloat`
- Produces: `WorkspacePanelLayout.terminalOffset(terminalHeight:panelInset:isVisible:) -> CGFloat`

- [ ] **Step 1: Write failing offset tests**

```swift
@Test func workspacePanelLayoutUsesFullDistanceOffsets() {
    #expect(WorkspacePanelLayout.sidebarOffset(
        sidebarWidth: 280,
        panelInset: 12,
        isVisible: false
    ) == -304)
    #expect(WorkspacePanelLayout.sidebarOffset(
        sidebarWidth: 280,
        panelInset: 12,
        isVisible: true
    ) == 0)
    #expect(WorkspacePanelLayout.terminalOffset(
        terminalHeight: 220,
        panelInset: 12,
        isVisible: false
    ) == 232)
    #expect(WorkspacePanelLayout.terminalOffset(
        terminalHeight: 220,
        panelInset: 12,
        isVisible: true
    ) == 0)
}
```

- [ ] **Step 2: Verify the tests fail**

Run the focused `AppModelTests` command from Task 1.

Expected: compilation fails because the two offset helpers do not exist.

- [ ] **Step 3: Implement constant-size motion**

Implement offsets that return zero when visible and the complete signed travel distance when hidden. In `WorkspaceView`, remove both panel `opacity` and `scaleEffect` modifiers, remove terminal-dependent sidebar bottom padding, and apply the helpers with `.easeInOut(duration: 0.20)`. When Reduce Motion is enabled, use no animation but retain the hidden offset.

- [ ] **Step 4: Verify focused tests and the terminal lifecycle regression**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -quiet -project SimpleCode.xcodeproj -scheme SimpleCode -destination 'platform=macOS' -only-testing:SimpleCodeTests/AppModelTests -only-testing:SimpleCodeTests/TerminalSessionControllerTests
```

Expected: all selected tests pass with zero failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/SimpleCode/Features/Workspace/WorkspaceModel.swift Sources/SimpleCode/Features/Workspace/WorkspaceView.swift Tests/SimpleCodeTests/AppModelTests.swift
git commit -m "fix: simplify panel transitions"
```

### Task 3: Audit, publish, and open the main project

**Files:**
- Verify: all committed source and test files

- [ ] **Step 1: Run the full unit suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -quiet -project SimpleCode.xcodeproj -scheme SimpleCode -destination 'platform=macOS' -only-testing:SimpleCodeTests
```

Expected: zero failures.

- [ ] **Step 2: Run the full macOS build**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild build -quiet -project SimpleCode.xcodeproj -scheme SimpleCode -destination 'platform=macOS'
```

Expected: exit code 0.

- [ ] **Step 3: Audit history and working tree**

Confirm every new commit has a one-line subject, an empty body, and no `Co-authored-by` trailer. Preserve the user's untracked `.superpowers/` directory and confirm all tracked files are clean.

- [ ] **Step 4: Remove obsolete isolation and push**

Remove the clean repair worktree and its local branch, then run:

```bash
git push origin main
```

Expected: `origin/main` advances to the verified main commit.

- [ ] **Step 5: Open the current main project**

```bash
open -a Xcode /Users/rainzhang/SimpleCode/SimpleCode.xcodeproj
```

Expected: Xcode opens the project from the updated main checkout.
