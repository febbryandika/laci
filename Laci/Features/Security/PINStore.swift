import Foundation
import Security

enum PINStoreError: Error, Hashable {
    case keychain(OSStatus)
    case unreadable
}

/// Where the PIN record lives. Main-actor, like the repositories: a Keychain read is quick and
/// only ever follows a tap.
@MainActor
protocol PINStoring: AnyObject {
    func load() throws -> PINRecord?
    func save(_ record: PINRecord) throws
    func delete() throws
}

/// One generic-password item. `AfterFirstUnlockThisDeviceOnly`: the same window as the store file,
/// and it never leaves this iPad in a device backup. Not a `WhenPasscodeSet` class, because a
/// counter iPad may have no passcode and such an item cannot even be written there.
final class KeychainPINStore: PINStoring {
    private let service: String

    init(service: String = "id.laci.pin") {
        self.service = service
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: "owner",
        ]
    }

    func load() throws -> PINRecord? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else { throw PINStoreError.keychain(status) }
        guard let data = result as? Data, let record = try? JSONDecoder().decode(PINRecord.self, from: data) else {
            throw PINStoreError.unreadable
        }
        return record
    }

    /// Update first, then add: deleting before adding could lose the PIN between the two calls.
    func save(_ record: PINRecord) throws {
        let data = try JSONEncoder().encode(record)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw PINStoreError.keychain(status) }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PINStoreError.keychain(status)
        }
    }
}

/// For previews and tests, and for UI tests, which must never touch the real Keychain.
final class InMemoryPINStore: PINStoring {
    private var record: PINRecord?

    init(record: PINRecord? = nil) {
        self.record = record
    }

    func load() -> PINRecord? {
        record
    }

    func save(_ record: PINRecord) {
        self.record = record
    }

    func delete() {
        record = nil
    }
}
