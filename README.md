# SimpleCode

SimpleCode is a lightweight native macOS code editor. SwiftUI owns the app
structure, windows, menus, settings, and workspace chrome; narrow AppKit bridges
own the opaque editing surface and the SwiftTerm-powered terminal surface.

The app is intentionally small. It includes workspace opening, recent workspaces,
local Git clone, file-tree operations, tabs, native text editing, syntax
highlighting, find/replace, go-to-line, save safeguards, settings, and a
trust-gated terminal run flow. It does not include LSP, debugging, source-control
UI, remote development, plugins, collaboration, or AI features.

## Requirements

- macOS 26 or later on Apple silicon.

## Privacy and Security Notes

The main app is not sandboxed. This is deliberate: the integrated terminal runs
inside the user's normal local shell environment, and run commands may read,
modify, or delete local files. SimpleCode gates run commands behind workspace
trust prompts, but users should still treat cloned repositories as untrusted code.

## Acknowledgments

Third-party dependency and license inventory is maintained in
`ACKNOWLEDGMENTS.md`. The Help menu opens the bundled README and acknowledgments
from the built app.

## License

MIT. See `LICENSE`.
