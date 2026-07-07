# Terminal Technical Spike — Findings

## Design, and what it is based on

`TerminalRepresentable` (`Sources/SimpleCode/Components/Terminal/TerminalRepresentable.swift`)
wraps SwiftTerm's `LocalProcessTerminalView` (`Sources/SwiftTerm/Mac/MacLocalTerminalView.swift`
in the pinned `v1.13.0` checkout — fetched and read directly, not guessed) via
`NSViewRepresentable`. `TerminalSessionController` owns intent (start / interrupt /
clear / restart / terminate) and a small, SwiftTerm-independent lifecycle enum,
`TerminalLifecycleState`, which is unit-tested on its own (`TerminalLifecycleStateTests`).

Confirmed directly from SwiftTerm's own source (not assumed):

- `LocalProcessTerminalView.startProcess(executable:args:environment:execName:currentDirectory:)`
  takes the working directory as a plain parameter — used with
  `ShellEnvironment.loginShellPath()` (resolved via the directory-services `pw_shell`
  record for the current user, the same source `Terminal.app` uses, not just the
  `SHELL` environment variable) and the workspace root.
- `environment` is an array of `"KEY=VALUE"` strings, not a dictionary — confirmed
  from `LocalProcess.startProcess`'s implementation, and matched in
  `TerminalSessionController.startIfNeeded()`.
- `LocalProcessTerminalView.terminate()` calls through to `LocalProcess.terminate()`,
  which sends `SIGTERM` to `shellPid` and tears down the PTY's `DispatchIO`/file
  descriptors. This is what `TerminalSessionController.terminate()` relies on to
  avoid leaving an orphaned child shell when a workspace closes or the app quits
  (wired through `WorkspaceModel.tearDown()` → `AppModel.closeWorkspace()` /
  `AppDelegate.applicationWillTerminate`).
- Ctrl-C is sent via `LocalProcessTerminalView.send([0x03])` (the view's own `send`
  API, which SwiftTerm forwards to the underlying `LocalProcess`) — not by reaching
  into private state.
- "Clear" sends the standard ANSI clear sequence (`\u{1B}[2J\u{1B}[3J\u{1B}[H`)
  through the same `send(txt:)` API, rather than assuming a SwiftTerm-specific
  "clear buffer" method exists (none was found in the fetched source).
- Light/dark palette adaptation sets `nativeBackgroundColor`/`nativeForegroundColor`/
  `caretColor`/`selectedTextBackgroundColor` to genuinely dynamic `NSColor`s
  (`ColorRolePair.dynamic`), the same mechanism the editor surface uses, rather than
  a one-time snapshot recomputed on some notification — confirmed by reading
  `AppleTerminalView.swift`'s drawing code, which calls `nativeBackgroundColor.setFill()`
  fresh on every draw pass.
- SwiftTerm's **standard AppKit rendering path** is used; the optional Metal renderer
  is not referenced anywhere in this codebase, per the brief.

## What could not be verified in this environment, and why

This sandbox has **Xcode Command Line Tools only — no Xcode.app, no Metal compiler,
no `SwiftUIMacros` plugin**. Two concrete, reproduced consequences for the terminal
spike specifically:

1. `swift build` fails while compiling SwiftTerm itself, because SwiftTerm 1.13.0's
   `Package.swift` unconditionally declares `resources: [.process("Apple/Metal/Shaders.metal")]`
   for its `SwiftTerm` target on macOS, and `.process`-ing a `.metal` file invokes the
   `metal` compiler, which does not exist outside a full Xcode install. This is true
   **even though this codebase never enables or references SwiftTerm's Metal
   renderer** — the shader is compiled unconditionally as part of building the
   dependency's default target, regardless of which renderer a consumer chooses at
   runtime. Reproduced verbatim; see "Dependency resolution" and "Test and build
   results" in the implementation report for the exact error and the diagnostic
   (never committed) workaround used to get further signal.
2. Even past that, the app target's own SwiftUI views fail to compile in this
   sandbox for an unrelated reason (`@State`'s `SwiftUIMacros` plugin is Xcode-only —
   see `EditorSpikeNotes.md`), which blocks ever reaching a running, on-screen
   terminal view in this specific sandbox.

Consequently, the following required checks were **not executed against a live
SwiftTerm session** and are not claimed to have passed:

- `pwd`, `ls`, a command producing colored output, a command producing many lines,
  an interruptible long-running command, repeated resizing, scrolling while output
  streams, and a composed/non-ASCII input string.

What *was* verified, at the operating-system level, independent of this Swift
codebase (useful supporting evidence, but explicitly **not** a substitute for the
checks above): this sandbox's own login shell is `/bin/zsh` (confirmed via
`dscl . -read /Users/<user> UserShell`, the same directory-services lookup
`ShellEnvironment.loginShellPath()` performs), `/bin/zsh` and `/bin/bash` exist and
are executable, and ANSI SGR color sequences render correctly in this sandbox's own
terminal. None of this exercises SwiftTerm's Swift API, forkpty-based
`LocalProcess`, or this codebase's `TerminalSessionController` — it only confirms the
underlying OS facts the design depends on are true in this environment.

## Recommended follow-up for the next phase

On a machine with full Xcode 26 installed (Metal compiler and `SwiftUIMacros`
present), run the app and manually execute the full check list above — `pwd`/`ls`,
colored output, a long-running command interrupted with Ctrl-C, repeated resizing,
scroll-while-streaming, and a non-ASCII/composed input string (e.g. an emoji with a
ZWJ sequence, or IME-composed text) — and record the actual observed behavior,
including any SwiftTerm quirks encountered, in this file.
