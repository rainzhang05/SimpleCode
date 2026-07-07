import Foundation
import Testing
@testable import SimpleCode

struct GitCloneProgressParserTests {
    @Test func receivingObjectsPhase() {
        var parser = GitCloneProgressParser()
        let progress = parser.append("Receiving objects: 50% (10/20)\r")
        #expect(progress.phase == .receiving)
        #expect(progress.percentage == 50)
        #expect(progress.receivedObjects == 10)
        #expect(progress.totalObjects == 20)
    }

    @Test func carriageReturnUpdates() {
        var parser = GitCloneProgressParser()
        _ = parser.append("Receiving objects:  10% ")
        let progress = parser.append("\rReceiving objects:  20% ")
        #expect(progress.percentage == 20)
    }

    @Test func partialUTF8Chunks() {
        var parser = GitCloneProgressParser()
        let bytes = Data("Counting objects: ".utf8)
        _ = parser.append(data: bytes)
        let progress = parser.append(data: Data("5\r".utf8))
        #expect(progress.phase == .counting)
    }

    @Test func unknownLinesDoNotFail() {
        var parser = GitCloneProgressParser()
        let progress = parser.append("Cloning into 'repo'...\n")
        #expect(progress.phase == .unknown)
        #expect(!progress.statusMessage.isEmpty)
    }

    @Test func multipleRecordsInOneRead() {
        var parser = GitCloneProgressParser()
        let progress = parser.append(
            "Cloning into 'repo'...\nremote: Counting objects: 3, done.\nReceiving objects:  33% (1/3)\r"
        )
        #expect(progress.phase == .receiving)
        #expect(progress.percentage == 33)
    }

    @Test func malformedPercentageIgnored() {
        var parser = GitCloneProgressParser()
        let progress = parser.append("Receiving objects: 999% (1/3)\r")
        #expect(progress.percentage == nil)
    }

    @Test func largeObjectCounts() {
        var parser = GitCloneProgressParser()
        let progress = parser.append("Receiving objects:  10% (100000/1000000)\r")
        #expect(progress.receivedObjects == 100_000)
        #expect(progress.totalObjects == 1_000_000)
    }

    @Test func checkoutPhase() {
        var parser = GitCloneProgressParser()
        let progress = parser.append("Checking out files:  50% (5/10)\r")
        #expect(progress.phase == .checkingOut)
    }

    @Test func phaseDoesNotRegress() {
        var parser = GitCloneProgressParser()
        _ = parser.append("Receiving objects:  50% (5/10)\r")
        let progress = parser.append("Counting objects: 3\r")
        #expect(progress.phase == .receiving)
    }

    @Test func errorInterleavedWithProgress() {
        var parser = GitCloneProgressParser()
        _ = parser.append("Receiving objects:  10% (1/10)\r")
        let progress = parser.append("fatal: authentication failed\n")
        #expect(!progress.statusMessage.isEmpty)
    }

    @Test func localCloneOutput() {
        var parser = GitCloneProgressParser()
        let progress = parser.append("Cloning into '/tmp/repo'...\n")
        #expect(progress.statusMessage.contains("Cloning"))
    }

    @Test func noPercentageAvailable() {
        var parser = GitCloneProgressParser()
        let progress = parser.append("Resolving deltas: 100% (3/3)\r")
        #expect(progress.phase == .resolving)
    }
}
