# SimpleCode Acknowledgments

SimpleCode includes or links the following third-party projects through Swift
Package Manager. Versions are pinned in `project.yml` and resolved in
`SimpleCode.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

| Project | Version | License | Use |
| --- | --- | --- | --- |
| SwiftTerm | 1.13.0 | MIT | Integrated terminal emulator |
| SwiftTreeSitter | 0.10.0 | BSD 3-Clause | Swift bindings for tree-sitter |
| tree-sitter | 0.25.10 | MIT | Parser runtime |
| tree-sitter-swift | 0.7.3-with-generated-files | MIT | Swift grammar |
| tree-sitter-c | 0.24.2 | MIT | C grammar |
| tree-sitter-cpp | 0.23.4 | MIT | C++ grammar |
| tree-sitter-json | 0.24.8 | MIT | JSON grammar |
| tree-sitter-markdown | 0.5.3 | MIT | Markdown grammar |
| tree-sitter-bash | 0.25.1 | MIT | Shell grammar |
| swift-argument-parser | 1.8.2 | Apache 2.0 | Transitive dependency |

Vendored query resources are stored under
`Sources/SimpleCode/Resources/TreeSitterQueries/`. The Swift query is a vendored
copy from `alex-pinkus/tree-sitter-swift`; other bundled query files are
project-local highlight queries written for SimpleCode's capture categories.

SimpleCode itself is distributed under the MIT license in `LICENSE`.
