#if DEBUG
import Foundation
import LintelKit
import Testing

@testable import LintelApp

/// `--qa-persistent-settings` keeps the throwaway QA keychain in the QA data root (#295). Synthetic data only.
@Suite struct QAFileKeychainClientTests {
    private func temporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "lintel-qa-keychain-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: QAFileKeychainClient.fileName)
    }

    @Test func anItemSurvivesANewClientOverTheSameFile() throws {
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = QAFileKeychainClient(url: url)
        try first.addGenericPassword(Data([1, 2, 3]), service: "svc", account: "acc")
        let second = QAFileKeychainClient(url: url)
        #expect(try second.readGenericPassword(service: "svc", account: "acc") == Data([1, 2, 3]))
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }

    @Test func aDuplicateIsRefusedAndADeleteSticks() throws {
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let client = QAFileKeychainClient(url: url)
        try client.addGenericPassword(Data([1]), service: "svc", account: "acc")
        #expect(throws: KeychainError.self) { try client.addGenericPassword(Data([2]), service: "svc", account: "acc") }
        try client.deleteGenericPassword(service: "svc", account: "acc")
        #expect(throws: KeychainError.itemNotFound) {
            try QAFileKeychainClient(url: url).readGenericPassword(service: "svc", account: "acc")
        }
        #expect(throws: KeychainError.itemNotFound) { try client.deleteGenericPassword(service: "svc", account: "acc") }
    }

    @Test func aMissingOrUnreadableFileStartsEmpty() throws {
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(throws: KeychainError.itemNotFound) {
            try QAFileKeychainClient(url: url).readGenericPassword(service: "a", account: "b")
        }
        try Data("not json".utf8).write(to: url)
        #expect(throws: KeychainError.itemNotFound) {
            try QAFileKeychainClient(url: url).readGenericPassword(service: "a", account: "b")
        }
    }
}
#endif
