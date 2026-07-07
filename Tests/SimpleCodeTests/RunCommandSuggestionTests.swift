import Foundation
import Testing
@testable import SimpleCode

@Suite(.serialized)
struct RunCommandSuggestionTests {
    private let service = RunCommandSuggestionService()

    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "Suggest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func swiftPackage() async throws {
        let root = try makeRoot()
        try "//".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let s = await service.suggest(rootURL: root)
        #expect(s?.command == "swift run")
    }

    @Test func makefile() async throws {
        let root = try makeRoot()
        try "".write(to: root.appendingPathComponent("Makefile"), atomically: true, encoding: .utf8)
        let s = await service.suggest(rootURL: root)
        #expect(s?.command == "make")
    }

    @Test func pythonUnambiguousEntry() async throws {
        let root = try makeRoot()
        try "print(1)".write(to: root.appendingPathComponent("main.py"), atomically: true, encoding: .utf8)
        let s = await service.suggest(rootURL: root)
        #expect(s?.command == "python3 main.py")
    }

    @Test func pythonAmbiguousReturnsNoSuggestion() async throws {
        let root = try makeRoot()
        try "a".write(to: root.appendingPathComponent("a.py"), atomically: true, encoding: .utf8)
        try "b".write(to: root.appendingPathComponent("b.py"), atomically: true, encoding: .utf8)
        let s = await service.suggest(rootURL: root)
        #expect(s == nil)
    }

    @Test func npmScripts() async throws {
        let root = try makeRoot()
        let json = #"{"scripts":{"dev":"vite","build":"tsc"}}"#
        try json.write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "".write(to: root.appendingPathComponent("package-lock.json"), atomically: true, encoding: .utf8)
        let s = await service.suggest(rootURL: root)
        #expect(s?.command == "npm run dev")
    }

    @Test func yarnLock() async throws {
        let root = try makeRoot()
        let json = #"{"scripts":{"start":"node index.js"}}"#
        try json.write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "".write(to: root.appendingPathComponent("yarn.lock"), atomically: true, encoding: .utf8)
        let s = await service.suggest(rootURL: root)
        #expect(s?.command == "yarn start")
    }

    @Test func pnpmLock() async throws {
        let root = try makeRoot()
        let json = #"{"scripts":{"start":"node index.js"}}"#
        try json.write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "".write(to: root.appendingPathComponent("pnpm-lock.yaml"), atomically: true, encoding: .utf8)
        let s = await service.suggest(rootURL: root)
        #expect(s?.command == "pnpm run start")
    }

    @Test func bunLock() async throws {
        let root = try makeRoot()
        let json = #"{"scripts":{"start":"bun run"}}"#
        try json.write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "".write(to: root.appendingPathComponent("bun.lockb"), atomically: true, encoding: .utf8)
        let s = await service.suggest(rootURL: root)
        #expect(s?.command == "bun run start")
    }

    @Test func cargo() async throws {
        let root = try makeRoot()
        try "[package]".write(to: root.appendingPathComponent("Cargo.toml"), atomically: true, encoding: .utf8)
        let s = await service.suggest(rootURL: root)
        #expect(s?.command == "cargo run")
    }

    @Test func goModule() async throws {
        let root = try makeRoot()
        try "module example.com".write(to: root.appendingPathComponent("go.mod"), atomically: true, encoding: .utf8)
        let s = await service.suggest(rootURL: root)
        #expect(s?.command == "go run .")
    }

    @Test func gradleWrapper() async throws {
        let root = try makeRoot()
        try "#!/bin/sh".write(to: root.appendingPathComponent("gradlew"), atomically: true, encoding: .utf8)
        let s = await service.suggest(rootURL: root)
        #expect(s?.command == "./gradlew run")
    }

    @Test func maven() async throws {
        let root = try makeRoot()
        try "<project/>".write(to: root.appendingPathComponent("pom.xml"), atomically: true, encoding: .utf8)
        let s = await service.suggest(rootURL: root)
        #expect(s?.command == "mvn compile exec:java")
    }

    @Test func xcodeProjectGuidanceOnly() async throws {
        let root = try makeRoot()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("App.xcodeproj"), withIntermediateDirectories: true)
        let s = await service.suggest(rootURL: root)
        #expect(s?.isRunnable == false)
        #expect(s?.confidence == .guidance)
    }

    @Test func malformedJSONSkipped() async throws {
        let root = try makeRoot()
        try "{not json".write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        let s = await service.suggest(rootURL: root)
        #expect(s == nil)
    }

    @Test func swiftPackageWinsOverMakefile() async throws {
        let root = try makeRoot()
        try "//".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "".write(to: root.appendingPathComponent("Makefile"), atomically: true, encoding: .utf8)
        let s = await service.suggest(rootURL: root)
        #expect(s?.command == "swift run")
    }

    @Test func cargoWinsOverPackageJSON() async throws {
        let root = try makeRoot()
        try "[package]".write(to: root.appendingPathComponent("Cargo.toml"), atomically: true, encoding: .utf8)
        try #"{"scripts":{"start":"node"}}"#.write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        let s = await service.suggest(rootURL: root)
        #expect(s?.command == "cargo run")
    }

    @Test func goModWinsOverMakefile() async throws {
        let root = try makeRoot()
        try "module x".write(to: root.appendingPathComponent("go.mod"), atomically: true, encoding: .utf8)
        try "".write(to: root.appendingPathComponent("Makefile"), atomically: true, encoding: .utf8)
        let s = await service.suggest(rootURL: root)
        #expect(s?.command == "go run .")
    }

    @Test func packageJSONNoScriptsReturnsNil() async throws {
        let root = try makeRoot()
        try #"{"name":"x"}"#.write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        let s = await service.suggest(rootURL: root)
        #expect(s == nil)
    }

    @Test func packageJSONDevScriptPreferred() async throws {
        let root = try makeRoot()
        try #"{"scripts":{"dev":"vite","start":"node"}}"#.write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        let s = await service.suggest(rootURL: root)
        #expect(s?.command == "npm run dev")
    }

    @Test func packageJSONStartWhenNoDev() async throws {
        let root = try makeRoot()
        try #"{"scripts":{"start":"node index.js"}}"#.write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        let s = await service.suggest(rootURL: root)
        #expect(s?.command == "npm run start")
    }

    @Test func multipleLockfilesPreferYarn() async throws {
        let root = try makeRoot()
        try #"{"scripts":{"start":"node"}}"#.write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "".write(to: root.appendingPathComponent("yarn.lock"), atomically: true, encoding: .utf8)
        try "".write(to: root.appendingPathComponent("package-lock.json"), atomically: true, encoding: .utf8)
        let s = await service.suggest(rootURL: root)
        #expect(s?.command == "yarn start")
    }

    @Test func oversizedPackageJSONSkipped() async throws {
        let root = try makeRoot()
        let huge = String(repeating: " ", count: 70_000)
        try huge.write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        let s = await service.suggest(rootURL: root)
        #expect(s == nil)
    }

    @Test func pyprojectWithoutEntryReturnsNil() async throws {
        let root = try makeRoot()
        try "[project]".write(to: root.appendingPathComponent("pyproject.toml"), atomically: true, encoding: .utf8)
        try "a".write(to: root.appendingPathComponent("a.py"), atomically: true, encoding: .utf8)
        try "b".write(to: root.appendingPathComponent("b.py"), atomically: true, encoding: .utf8)
        let s = await service.suggest(rootURL: root)
        #expect(s == nil)
    }

    @Test func xcodeWorkspaceGuidanceOnly() async throws {
        let root = try makeRoot()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("App.xcworkspace"), withIntermediateDirectories: true)
        let s = await service.suggest(rootURL: root)
        #expect(s?.isRunnable == false)
    }

    @Test func noRecognizedProjectType() async throws {
        let root = try makeRoot()
        try "readme".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let s = await service.suggest(rootURL: root)
        #expect(s == nil)
    }

    @Test func guidanceSuggestionNotRunnable() async throws {
        let root = try makeRoot()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("App.xcodeproj"), withIntermediateDirectories: true)
        let s = await service.suggest(rootURL: root)
        #expect(s?.command == nil)
        #expect(s?.isRunnable == false)
    }
}
