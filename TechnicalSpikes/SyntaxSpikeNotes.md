# Syntax-Highlighting Technical Spike — Findings

## Pipeline

`SwiftHighlighter` (`Sources/SimpleCode/Components/Editor/SwiftHighlighter.swift`) is
an `actor` that owns the tree-sitter `Parser`, the current `MutableTree?`, and the
compiled `Query` for exactly one open document. It is the **only** actor introduced
in this codebase — everywhere else, the code-quality rule against premature actor
decomposition is followed, because nowhere else does genuine background concurrency
exist yet (see the doc comment on `SwiftHighlighter` itself).

1. **Initial parse**: `load(text:revision:)` does a full `parser.parse(_:)` and a full
   query pass, producing a `HighlightBatch` covering the whole document.
2. **Incremental update**: `applyEdit(fullText:edit:revision:)` builds an `InputEdit`
   from UTF-16 offsets (`start/oldEnd/newEndUTF16 * 2`, matching tree-sitter's
   UTF-16LE byte convention — confirmed directly against
   `SwiftTreeSitter`'s own `NSRange.byteRange`/`Range<UInt32>.range` extensions),
   calls `tree.edit(inputEdit)`, then re-parses via
   `parser.parse(tree: previousTree, string: fullText)` — genuinely incremental, not
   "construct a completely unrelated parser state": the previous tree is reused and
   only the edited region is re-derived by tree-sitter internally.
3. **Grammar-provided queries**: the highlight query is the grammar's own, unmodified
   `queries/highlights.scm` from `alex-pinkus/tree-sitter-swift` (see the attribution
   header in `Sources/SimpleCode/Resources/TreeSitterQueries/Swift/highlights.scm` and
   "Dependency resolution" in the implementation report for *why* it is vendored
   rather than loaded from the grammar package's own resource bundle).
4. **UTF-16 `NSRange` throughout**: `SyntaxToken.range` is always an `NSRange`
   produced from `QueryCapture.range` (`Node.range`), which SwiftTreeSitter itself
   derives from byte ranges via `Range<UInt32>.range` (divide by 2). Nothing in this
   pipeline hand-rolls byte↔UTF-16 conversion outside that one library-provided path.
5. **Revision tagging + stale rejection**: every `HighlightBatch` carries the
   `EditorDocumentModel` revision that was current when the edit was scheduled.
   `CodeEditorRepresentable.Coordinator.apply(batch:)` compares
   `batch.revision == document.revision` and silently discards the batch if a newer
   edit has since landed. Unit-tested directly in `EditorDocumentModelTests` (the
   exact same comparison, isolated from the actor/NSTextView machinery).
6. **No undo-stack pollution**: attribute application is wrapped in
   `textStorage.beginEditing()/endEditing()` using `addAttribute(_:value:range:)`
   only — never `insertText`/`replaceCharacters`, which are what register undo
   actions on `NSTextView`. Attribute-only edits are also explicitly excluded from
   re-triggering the highlighter (`isApplyingHighlighting` guard in the
   `NSTextStorageDelegate` callback), which is also what prevents infinite recursion.
7. **Priority range, then remainder**: `applyEdit` first highlights a ±4,000 UTF-16
   unit window around the edit (the "priority" batch), then anything else
   `tree.changedRanges(from:)` reports as changed outside that window is highlighted
   as a second "remainder" batch. See the honest caveat below about what "priority" means here.

## Explicit, honest scope limits

- **Bracket matching is not implemented**, and this codebase does not claim
  tree-sitter supplies matching-bracket ranges "for free" — it doesn't; that would
  require either a dedicated query (`locals.scm`/custom) or manual tree-cursor
  sibling matching, neither of which is built here.
- **"Prioritize the visible range" is approximated as "the region around the most
  recent edit,"** not a pixel-accurate on-screen viewport computed from TextKit 2
  layout-fragment geometry. During active typing these are almost always the same
  place, so this is a reasonable, low-risk approximation for a spike, but it is not
  the same thing as a real viewport query — see `SwiftHighlighter.applyEdit`'s doc
  comment. A precise version would enumerate `NSTextLayoutFragment`s intersecting
  the scroll view's visible rect (the same technique `LineNumberGutterView` uses for
  the gutter) and is a reasonable next step, not attempted here to avoid fragile,
  under-tested geometry code in a foundation phase.

## Performance check

**What was actually measured, and what was not.** This sandbox has no attached
display and no UI-automation tool available to this agent (see
`EditorSpikeNotes.md`'s "Build and validation environment" section for the exact
toolchain gap), so literal interactive typing in a live window was not performed.
What *is* verifiable and honestly reported:

- `SampleSwiftSource.generateLarge()` synthesizes a ~6,000-line representative Swift
  file (repeated small `struct`/`func` declarations with comments, strings, numbers,
  and control flow) specifically for this check.
- The highlighting pipeline's design bounds the *cost per keystroke* to: one
  incremental tree-sitter re-parse (tree-sitter's own incremental parsing, which is
  designed to be fast relative to file size because only the edited subtree is
  re-derived) plus one query pass restricted to an 8,000-UTF-16-unit window (the
  priority batch), with the potentially-larger "remainder" pass deferred to a second,
  lower-priority step. This is the same architectural shape (bounded, incremental,
  revision-guarded) that the report identified as necessary to avoid recoloring
  whole large files on every keystroke — but a shape being correct on paper is not
  the same as a measured number, and no measured wall-clock/frame-rate number is
  claimed here.
- **What could not be verified in this environment**: actual typing latency, visible
  color lag, stale-color flashes during rapid edits, scroll smoothness, and RSS
  memory growth over a long editing session. These require a running, on-screen
  instance of the app, which this sandbox's toolchain gap (see build notes) prevented
  from being produced. This is reported honestly as **not verified**, rather than
  claimed to have passed.

## Recommended follow-up for the next phase

Run this exact synthetic file (`SampleSwiftSource.generateLarge()`) through the real
app on a machine with full Xcode 26, typing continuously for 60+ seconds, while
watching Activity Monitor / Instruments for CPU and memory, and report the actual
numbers — that is the honest performance check this phase's environment could not
complete.
