# Editor Technical Spike — Findings

## TextKit decision

`CodeTextView` (`Sources/SimpleCode/Components/Editor/CodeTextView.swift`) opts into
one TextKit 2 object graph with AppKit's dedicated initializer:

```
NSTextView(usingTextLayoutManager: true)
```

The resulting `NSTextContentStorage` owns the session's `NSTextStorage`, preserving
one storage/layout/view path when tabs change. Do not construct this editor with
`NSTextView(frame:textContainer:)`: it takes the legacy compatibility path even when
given a TextKit 2 container. Likewise, do not read `textView.layoutManager` or use
glyph-range APIs on this view; use `textLayoutManager`, `NSTextContentManager`, and
layout fragments only. `CodeTextView.isUsingTextKit2` exposes
`textLayoutManager != nil` as the non-destructive runtime check.

**No fallback to TextKit 1 is required.** The legacy `layoutManager` accessor and
`NSScrollView.verticalRulerView` / `NSRulerView` integration must be avoided: the
latter suppressed visible glyph rendering in the real UI screenshot test. The gutter
therefore draws from TextKit 2 fragments as a noninteractive `NSTextView` subview in
space reserved by `textContainerInset`, rather than as a vertical ruler.

## What works

- Multiline editing, vertical **and** horizontal scrolling (non-wrapping container,
  classic `isHorizontallyResizable`/`isVerticallyResizable` recipe).
- Monospaced system font (`Typography.editorFont(size:)`), configurable size via
  `EditorSettingsStore`, wired to a toolbar stepper — a one-way flow from SwiftUI into
  the view (`updateNSView` only ever *reads* `fontSize`, never text).
- Standard selection, copy/cut/paste, and undo/redo remain on `NSTextView`'s native
  responder path. The code-specific Return/Tab/Backspace/Home hooks preserve marked
  text and delegate only the edits that require editor semantics.
- Unicode text storage — `NSTextStorage`/`NSTextContentStorage` are Unicode-native;
  nothing in this phase re-encodes or transforms the text.
- Marked text/IME — command hooks defer to `NSTextView` whenever marked text is
  active, so composition stays on AppKit's native path.
- Light/dark adaptation — `ColorRole` dynamic `NSColor`s re-resolve automatically on
  every draw pass (`setFill()`/property reads inside `draw(_:)` and
  `configureForCodeEditing()`); no manual appearance-change observer is needed for the
  editor surface.
- Line-number gutter (`LineNumberGutterView`, a noninteractive editor subview in the
  reserved inset) and current-line highlight (`CodeTextView.drawCurrentLineHighlight()`),
  both TextKit-2-driven.
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

## Line-number indexing

`LineStartIndex` shifts UTF-16 line starts incrementally for ordinary character edits
and rebuilds only structural line-ending edits. That deliberately includes
equal-length replacements, CRLF boundaries, and deletions, where a small full-index
scan is safer than fragile boundary arithmetic. The gutter enumerates only visible
TextKit 2 fragments, so it does not rescan the full document on every redraw.

## Build and validation environment

The repair was built and tested with full Xcode beta:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project SimpleCode.xcodeproj -scheme SimpleCode -destination 'platform=macOS' \
  -only-testing:SimpleCodeTests/EditorVisibleRangeTests \
  -only-testing:SimpleCodeTests/LineStartIndexTests

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project SimpleCode.xcodeproj -scheme SimpleCode -destination 'platform=macOS' \
  -only-testing:SimpleCodeUITests/SimpleCodeUITests/testEditorPaintsGlyphsForSwiftAndPlainTextFiles
```

The focused unit run passed 17 tests, including equal-length newline replacement and
partial-CRLF deletion. The UI regression test opens both Swift and plain-text files,
then inspects screenshots for painted source glyphs (excluding the gutter) and visible
line-number labels; it does not rely on accessibility text alone. Its direct run is
currently deferred because a separately opened user-owned SimpleCode document has
unsaved changes and the runner must not terminate it. Manual free-form typing and
long horizontal-scroll inspection remain useful follow-up checks.
