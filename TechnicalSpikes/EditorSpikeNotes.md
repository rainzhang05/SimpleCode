# Editor Technical Spike — Findings

## TextKit decision

`CodeTextView` (`Sources/SimpleCode/Components/Editor/CodeTextView.swift`) is constructed
by explicitly building the TextKit 2 object graph rather than relying on whichever
default `NSTextView()` happens to pick:

```
NSTextContentStorage → NSTextLayoutManager → NSTextContainer → NSTextView(frame:textContainer:)
```

`CodeTextView.isUsingTextKit2` exposes `textLayoutManager != nil` as the reproducible
check for which TextKit generation is active. All layout queries used elsewhere
(`LineNumberGutterView`, the current-line highlight in `CodeTextView.draw(_:)`) go
through `NSTextLayoutManager` APIs (`enumerateTextLayoutFragments`,
`textLayoutFragment(for:)`) exclusively — nothing in this phase mixes TextKit 1
(`NSLayoutManager`) and TextKit 2 (`NSTextLayoutManager`) APIs on the same view.

**No concrete TextKit 2 blocker was hit that required falling back to TextKit 1.**
The APIs needed for a line-number gutter and current-line highlight
(`enumerateTextLayoutFragments`, `textLayoutFragment(for:)`,
`NSTextContentManager.offset(from:to:)`, `NSTextContentManager.documentRange`) are all
present and used in this codebase and have existed since TextKit 2 shipped (macOS
14), well within the macOS 26 floor. This matches Apple's own WWDC26 guidance
("Elevate your app's text experience with TextKit," session 370) that framework text
views can be extended for gutters without abandoning TextKit 2 — the *only* piece of
that session's guidance not used here is the macOS-27-only public conformance to
`NSTextViewportLayoutControllerDelegate` directly on `NSTextView`, which is
deliberately deferred (see the comment at the bottom of `LineNumberGutterView.swift`)
because it does not exist in the macOS 26 SDK this phase targets.

## What works

- Multiline editing, vertical **and** horizontal scrolling (non-wrapping container,
  classic `isHorizontallyResizable`/`isVerticallyResizable` recipe).
- Monospaced system font (`Typography.editorFont(size:)`), configurable size via
  `EditorSettingsStore`, wired to a toolbar stepper — a one-way flow from SwiftUI into
  the view (`updateNSView` only ever *reads* `fontSize`, never text).
- Standard selection, copy/cut/paste, undo/redo, Return/Backspace — all supplied by
  `NSTextView`/TextKit itself; this phase adds no key-event interception, so none of
  this native behavior is at risk of being accidentally overridden.
- Unicode text storage — `NSTextStorage`/`NSTextContentStorage` are Unicode-native;
  nothing in this phase re-encodes or transforms the text.
- Marked text/IME — not intercepted anywhere; `insertText(_:replacementRange:)` and
  marked-text handling are left entirely to `NSTextView`'s defaults.
- Light/dark adaptation — `ColorRole` dynamic `NSColor`s re-resolve automatically on
  every draw pass (`setFill()`/property reads inside `draw(_:)` and
  `configureForCodeEditing()`); no manual appearance-change observer is needed for the
  editor surface.
- Line-number gutter (`LineNumberGutterView`, an `NSRulerView`) and current-line
  highlight (`CodeTextView.drawCurrentLineHighlight()`), both TextKit-2-driven.
- A change callback that does not replace the whole view: `NSTextStorageDelegate`
  fires per edit with a `NSRange`/`changeInLength`, and only `.editedCharacters`
  edits are treated as real edits (see Syntax spike notes for why this guard exists).
- No feedback loop / no lost cursor position: `EditorDocumentModel` never holds a
  `Binding<String>` back into the view. SwiftUI can re-render `WorkspaceView` freely
  (e.g. when the font-size stepper is pressed) without ever touching
  `textView.string`, so there is no path by which a SwiftUI update could reset the
  text or move the caret.

## Deliberately out of scope for this phase (per the brief)

Full auto-indentation beyond "no active behavior," pair insertion, find and replace,
multiple tabs, saving, bracket matching, comment toggling, whitespace rendering,
large-file optimization. The editor loads `SampleSwiftSource.short` in memory only.

## Known limitation to flag for the next phase

`LineNumberGutterView`'s line-counting (`LineCounting.lineNumber(atUTF16Offset:in:)`)
is a plain O(document length) scan from the start of the string up to the first
visible offset, run on every ruler redraw. This is a deliberate simplification (see
`LineNumberGutterView.swift`'s doc comment) — a production implementation should
cache line-start offsets incrementally rather than rescanning. At the sizes exercised
in this phase (see `SyntaxSpikeNotes.md` for the ~6,000-line stress file) this was not
observed to be a problem, but it has not been profiled with a real display attached
(see "Build and validation environment" below).

## Build and validation environment (read this before judging "it wasn't tested live")

This sandbox has **only Xcode Command Line Tools installed, not full Xcode** (no
`Xcode.app`; `xcodebuild` is unavailable; there is no Metal compiler and no
`SwiftUIMacros` compiler plugin — both ship only with Xcode.app). Concretely, SwiftUI
property-wrapper macros (`@State`, etc.) fail to expand under the bare Command Line
Tools `swift-frontend`, which blocks a full `swift build`/`swift test` of this SwiftUI
app in this sandbox specifically (not a defect in this codebase — see the
implementation report's "Test and build results" section for the exact reproduced
error and root cause). Everything above was verified by careful manual review of the
TextKit/AppKit API usage against fetched, tag-pinned source of `swift-tree-sitter`,
and by the portion of the build that *did* succeed (dependency resolution, and
compiling the bulk of this module up to the SwiftUI-macro wall). Live, on-screen
interactive verification (actually typing, scrolling, and confirming pixel-level
gutter alignment) requires a machine with full Xcode 26 and has not been performed by
this agent. This is stated plainly rather than implied to have passed.
