#if DEBUG
import Foundation
import LintelKit
import Synchronization

/// DEBUG-only (`--qa-persistent-settings`): a keychain that survives a relaunch of a QA run, kept in a JSON file inside
/// the QA data root (`qa-keychain.json`, mode 0600). The items are throwaway keys of an isolated QA library, never
/// the real login keychain; without this a restart would lose the library key and the library would be archived
/// (#295 needs a real restart to be checked).
nonisolated final class QAFileKeychainClient: KeychainClient {
    static let fileName = "qa-keychain.json"

    private let url: URL
    private let items: Mutex<[String: Data]>

    init(url: URL) {
        self.url = url
        let stored = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: Data].self, from: $0) }
        items = Mutex(stored ?? [:])
    }

    private static func key(_ service: String, _ account: String) -> String { "\(service)\u{0}\(account)" }

    private func persist(_ items: [String: Data]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func readGenericPassword(service: String, account: String) throws(KeychainError) -> Data {
        guard let data = items.withLock({ $0[Self.key(service, account)] }) else { throw KeychainError.itemNotFound }
        return data
    }

    func addGenericPassword(_ data: Data, service: String, account: String) throws(KeychainError) {
        let added = items.withLock { items -> Bool in
            let key = Self.key(service, account)
            guard items[key] == nil else { return false }
            items[key] = data
            persist(items)
            return true
        }
        guard added else { throw KeychainError.unexpected(status: errSecDuplicateItem) }
    }

    func deleteGenericPassword(service: String, account: String) throws(KeychainError) {
        let removed = items.withLock { items -> Bool in
            guard items.removeValue(forKey: Self.key(service, account)) != nil else { return false }
            persist(items)
            return true
        }
        guard removed else { throw KeychainError.itemNotFound }
    }
}
#endif
