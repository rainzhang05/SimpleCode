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
- Xcode 26 or later for local development and release validation.
- XcodeGen 2.45.4 or later.

`project.yml` is the source of truth for targets, resources, dependencies,
bundle metadata, signing settings, and entitlements. Regenerate
`SimpleCode.xcodeproj` after any project-level change:

```sh
xcodegen generate
```

## Build and Test

Use stable Xcode 26 when available. If only the beta app is installed, make the
developer directory explicit and record that stable-Xcode validation is still
external:

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
```

Build Debug and Release for Apple silicon:

```sh
xcodebuild -project SimpleCode.xcodeproj -scheme SimpleCode \
  -configuration Debug -destination 'platform=macOS,arch=arm64' build

xcodebuild -project SimpleCode.xcodeproj -scheme SimpleCode \
  -configuration Release -destination 'platform=macOS,arch=arm64' build
```

Run unit tests without executing automated UI tests:

```sh
xcodebuild -project SimpleCode.xcodeproj -scheme SimpleCode \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:SimpleCodeTests test
```

Build the UI-test target for compile coverage:

```sh
xcodebuild -project SimpleCode.xcodeproj -scheme SimpleCode \
  -destination 'platform=macOS,arch=arm64' build-for-testing
```

Do not pass `CODE_SIGNING_ALLOWED=NO` for ordinary local Debug runs or XCUITest
runs. Unsigned Debug products can trigger macOS "damaged" launch failures for
test runners. The release QA archive command below is the exception because it is
used only for unsigned inspection.

## Release Archive

Create an unsigned inspection archive:

```sh
xcodebuild -project SimpleCode.xcodeproj -scheme SimpleCode \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath build/SimpleCode.xcarchive \
  CODE_SIGNING_ALLOWED=NO archive
```

Inspect the archive before signing:

```sh
APP=build/SimpleCode.xcarchive/Products/Applications/SimpleCode.app
file "$APP/Contents/MacOS/SimpleCode"
lipo -archs "$APP/Contents/MacOS/SimpleCode"
plutil -p "$APP/Contents/Info.plist"
codesign -d --entitlements :- "$APP" 2>/dev/null
codesign -dvv "$APP" 2>&1
otool -L "$APP/Contents/MacOS/SimpleCode"
```

Expected release metadata:

- Bundle identifier: `com.simplecode.app`
- Version: `0.1.0`
- Build: `1`
- Minimum macOS: `26.0`
- Architecture: `arm64`
- App sandbox: disabled for the main app
- Hardened runtime: enabled for signed Release distribution

## Signing and Notarization

Use environment variables for credentials; never commit secrets.

```sh
export SIMPLECODE_DEVELOPER_ID_APPLICATION='Developer ID Application: Example (TEAMID)'
export SIMPLECODE_KEYCHAIN_PROFILE='simplecode-notary-profile'
export SIMPLECODE_TEAM_ID='TEAMID'
```

Developer ID signing:

```sh
codesign --force --deep --options runtime --timestamp \
  --sign "$SIMPLECODE_DEVELOPER_ID_APPLICATION" \
  build/SimpleCode.xcarchive/Products/Applications/SimpleCode.app
```

Package and notarize:

```sh
ditto -c -k --keepParent \
  build/SimpleCode.xcarchive/Products/Applications/SimpleCode.app \
  build/SimpleCode.zip

xcrun notarytool submit build/SimpleCode.zip \
  --keychain-profile "$SIMPLECODE_KEYCHAIN_PROFILE" \
  --team-id "$SIMPLECODE_TEAM_ID" \
  --wait

xcrun stapler staple \
  build/SimpleCode.xcarchive/Products/Applications/SimpleCode.app
spctl --assess --type execute --verbose=4 \
  build/SimpleCode.xcarchive/Products/Applications/SimpleCode.app
```

## Syntax Highlighting

Tree-sitter grammars are linked through Swift Package Manager as declared in
`project.yml`. Query files live under
`Sources/SimpleCode/Resources/TreeSitterQueries/`.

Tree-sitter backed languages: Swift, C, C++, JSON, Markdown, and Shell.

Pattern fallback languages: JavaScript, TypeScript, TSX, Python, and Assembly.
JavaScript, TypeScript, TSX, and Python use the fallback intentionally because
their upstream package scanner/resource behavior was not release-validated for
this app. Unused JavaScript, Python, TypeScript, and TSX tree-sitter resources are
not bundled.

## Manual QA

Manual release QA should use throwaway workspaces only. Cover welcome recents,
create/open/clone, file-tree operations, editor tabs, find/replace, go-to-line,
large-file and binary-file handling, conflict banners, settings tabs, terminal
visibility, trust prompts, light/dark appearance, resizing, keyboard focus, and
scroll behavior.

Only use harmless terminal commands during release QA:

```sh
pwd
ls
printf 'simplecode-run-test\n'
export SIMPLECODE_TEST_VALUE=preserved
printf '%s\n' "$SIMPLECODE_TEST_VALUE"
```

Use local bare Git repositories for clone QA. Do not use public HTTPS clone tests
unless network use has been explicitly approved for that run.

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
