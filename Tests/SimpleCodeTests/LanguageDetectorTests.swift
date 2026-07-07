import Foundation
import Testing
@testable import SimpleCode

struct LanguageDetectorTests {
    // MARK: - Override

    @Test func overrideTakesPrecedenceOverExtension() {
        let url = URL(fileURLWithPath: "/tmp/script.py")
        let detected = LanguageDetector.detect(url: url, content: "#!/bin/bash", override: .swift)
        #expect(detected == .swift)
    }

    // MARK: - Exact filenames (case insensitive)

    @Test func detectsMakefileCaseInsensitive() {
        let lower = URL(fileURLWithPath: "/project/makefile")
        let upper = URL(fileURLWithPath: "/project/MAKEFILE")
        #expect(LanguageDetector.detect(url: lower) == .shell)
        #expect(LanguageDetector.detect(url: upper) == .shell)
    }

    @Test func detectsGNUmakefile() {
        let url = URL(fileURLWithPath: "/project/GNUmakefile")
        #expect(LanguageDetector.detect(url: url) == .shell)
    }

    @Test func detectsDotBashrc() {
        let url = URL(fileURLWithPath: "/home/user/.bashrc")
        #expect(LanguageDetector.detect(url: url) == .shell)
    }

    // MARK: - Extensions (case insensitive)

    @Test func detectsSwiftExtension() {
        let url = URL(fileURLWithPath: "/src/App.SWIFT")
        #expect(LanguageDetector.detect(url: url) == .swift)
    }

    @Test func detectsCExtension() {
        #expect(LanguageDetector.detect(url: URL(fileURLWithPath: "/src/main.c")) == .c)
    }

    @Test func detectsCppExtensions() {
        let extensions = ["cpp", "cc", "cxx", "hpp", "hh", "hxx"]
        for ext in extensions {
            let url = URL(fileURLWithPath: "/src/file.\(ext)")
            #expect(LanguageDetector.detect(url: url) == .cpp)
        }
    }

    @Test func detectsPythonExtensions() {
        for ext in ["py", "pyw", "pyi"] {
            let url = URL(fileURLWithPath: "/src/module.\(ext)")
            #expect(LanguageDetector.detect(url: url) == .python)
        }
    }

    @Test func detectsJavaScriptExtensions() {
        for ext in ["js", "mjs", "cjs", "jsx"] {
            let url = URL(fileURLWithPath: "/src/app.\(ext)")
            #expect(LanguageDetector.detect(url: url) == .javascript)
        }
    }

    @Test func detectsTypeScriptExtensions() {
        for ext in ["ts", "mts", "cts"] {
            let url = URL(fileURLWithPath: "/src/app.\(ext)")
            #expect(LanguageDetector.detect(url: url) == .typescript)
        }
    }

    @Test func detectsTSXExtension() {
        #expect(LanguageDetector.detect(url: URL(fileURLWithPath: "/src/App.tsx")) == .tsx)
    }

    @Test func detectsJSONExtensions() {
        for ext in ["json", "jsonc"] {
            let url = URL(fileURLWithPath: "/data/config.\(ext)")
            #expect(LanguageDetector.detect(url: url) == .json)
        }
    }

    @Test func detectsMarkdownExtensions() {
        for ext in ["md", "markdown", "mdown", "mkd"] {
            let url = URL(fileURLWithPath: "/docs/readme.\(ext)")
            #expect(LanguageDetector.detect(url: url) == .markdown)
        }
    }

    @Test func detectsShellExtensions() {
        for ext in ["sh", "bash", "zsh", "ksh"] {
            let url = URL(fileURLWithPath: "/bin/script.\(ext)")
            #expect(LanguageDetector.detect(url: url) == .shell)
        }
    }

    @Test func detectsAssemblyExtensions() {
        for ext in ["s", "asm", "S"] {
            let url = URL(fileURLWithPath: "/src/entry.\(ext)")
            #expect(LanguageDetector.detect(url: url) == .assembly)
        }
    }

    // MARK: - Header heuristic

    @Test func headerDefaultsToCWithoutCppSignal() {
        let url = URL(fileURLWithPath: "/include/widget.h")
        let context = LanguageWorkspaceContext(siblingExtensions: ["c", "h"])
        #expect(LanguageDetector.detect(url: url, workspaceContext: context) == .c)
    }

    @Test func headerDefaultsToCppWithNearbyCppFiles() {
        let url = URL(fileURLWithPath: "/include/widget.h")
        let context = LanguageWorkspaceContext(siblingExtensions: ["cpp", "h"])
        #expect(LanguageDetector.detect(url: url, workspaceContext: context) == .cpp)

        let ccContext = LanguageWorkspaceContext(siblingExtensions: ["cc"])
        #expect(LanguageDetector.detect(url: url, workspaceContext: ccContext) == .cpp)
    }

    // MARK: - Shebang

    @Test func detectsPythonShebang() {
        let url = URL(fileURLWithPath: "/tmp/script")
        let content = "#!/usr/bin/env python3\nprint('hi')\n"
        #expect(LanguageDetector.detect(url: url, content: content) == .python)
    }

    @Test func detectsBashShebang() {
        let url = URL(fileURLWithPath: "/tmp/script")
        let content = "#!/bin/bash\necho hi\n"
        #expect(LanguageDetector.detect(url: url, content: content) == .shell)
    }

    @Test func detectsNodeShebang() {
        let url = URL(fileURLWithPath: "/tmp/script")
        let content = "#!/usr/bin/env node\nconsole.log('hi')\n"
        #expect(LanguageDetector.detect(url: url, content: content) == .javascript)
    }

    // MARK: - Plain text fallback

    @Test func unknownExtensionFallsBackToPlainText() {
        let url = URL(fileURLWithPath: "/tmp/notes.txt")
        #expect(LanguageDetector.detect(url: url) == .plainText)
    }

    // MARK: - Makefile tab override

    @Test func makefileDefinitionForcesTabInsertion() {
        let url = URL(fileURLWithPath: "/project/Makefile")
        let definition = LanguageRegistry.definition(for: .shell, url: url)
        #expect(definition.insertSpacesOverride == false)
    }

    @Test func regularShellFileDoesNotForceTabInsertion() {
        let url = URL(fileURLWithPath: "/project/build.sh")
        let definition = LanguageRegistry.definition(for: .shell, url: url)
        #expect(definition.insertSpacesOverride == nil)
    }

    // MARK: - Registry completeness

    @Test func registryContainsAllTwelveLanguages() {
        #expect(LanguageRegistry.all.count == 12)
        #expect(Set(LanguageRegistry.all.map(\.id)) == Set(LanguageID.allCases))
    }

    @Test func documentLanguageTypealiasPreservesDisplayName() {
        let language: DocumentLanguage = .typescript
        #expect(language.displayName == "TypeScript")
    }
}
