import Foundation
@testable import Laci
import Security
import Testing

@MainActor
private final class FailingPINStore: PINStoring {
    var failsLoad = false
    var failsSave = false
    var failsDelete = false
    var record: PINRecord?

    func load() throws -> PINRecord? {
        if failsLoad {
            throw PINStoreError.keychain(-34018)
        }
        return record
    }

    func save(_ record: PINRecord) throws {
        if failsSave {
            throw PINStoreError.keychain(-34018)
        }
        self.record = record
    }

    func delete() throws {
        if failsDelete {
            throw PINStoreError.keychain(-34018)
        }
        record = nil
    }
}

@MainActor
@Suite("App lock")
struct AppLockTests {
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "AppLockTests-\(UUID().uuidString)"))
        // An install that has already run: the first-run wipe has its own tests below.
        defaults.set(true, forKey: "security.pinInstallMarker")
    }

    private func lock(_ store: any PINStoring = InMemoryPINStore()) -> AppLock {
        AppLock(store: store, biometrics: NoBiometrics(), defaults: defaults)
    }

    @Test("Setup stores a verifiable PIN and refuses a second one")
    func setup() throws {
        let lock = lock()
        #expect(lock.status == .noPIN)
        try lock.setInitialPIN("123456")
        #expect(lock.status == .set)
        #expect(lock.verify("123456"))
        #expect(!lock.verify("654321"))
        #expect(throws: AppLockError.storeFailed) { try lock.setInitialPIN("654321") }
        #expect(lock.verify("123456"))
    }

    @Test("A malformed PIN is refused", arguments: ["12345", "abcdef", "1234567"])
    func malformed(pin: String) {
        let lock = lock()
        #expect(throws: AppLockError.invalidFormat) { try lock.setInitialPIN(pin) }
        #expect(lock.status == .noPIN)
    }

    @Test("Change needs the current PIN and leaves it in force on refusal")
    func change() throws {
        let lock = lock()
        try lock.setInitialPIN("123456")
        #expect(throws: AppLockError.wrongPIN) { try lock.change(currentPIN: "000000", to: "654321") }
        #expect(lock.verify("123456"))
        try lock.change(currentPIN: "123456", to: "654321")
        #expect(lock.verify("654321"))
        #expect(!lock.verify("123456"))
    }

    @Test("Reset needs the current PIN, and only then removes it")
    func reset() throws {
        let lock = lock()
        try lock.setInitialPIN("123456")
        #expect(throws: AppLockError.wrongPIN) { try lock.reset(currentPIN: "000000") }
        #expect(lock.status == .set)
        try lock.reset(currentPIN: "123456")
        #expect(lock.status == .noPIN)
        #expect(!lock.verify("123456"))
    }

    @Test("A Keychain read error is not 'no PIN': nobody can set one over the owner's")
    func unreadableFailsClosed() {
        let store = FailingPINStore()
        store.failsLoad = true
        let lock = lock(store)
        #expect(lock.status == .unreadable)
        #expect(!lock.verify("123456"))
        #expect(throws: AppLockError.storeFailed) { try lock.setInitialPIN("123456") }
        #expect(store.record == nil)
    }

    @Test("A failed write leaves the status as it was")
    func writeFailure() {
        let store = FailingPINStore()
        store.failsSave = true
        let lock = lock(store)
        #expect(throws: AppLockError.storeFailed) { try lock.setInitialPIN("123456") }
        #expect(lock.status == .noPIN)
    }

    @Test("A failed delete leaves the PIN in force")
    func deleteFailure() throws {
        let store = FailingPINStore()
        let lock = lock(store)
        try lock.setInitialPIN("123456")
        store.failsDelete = true
        #expect(throws: AppLockError.storeFailed) { try lock.reset(currentPIN: "123456") }
        #expect(lock.status == .set)
        #expect(lock.verify("123456"))
    }

    @Test("The first launch of an install clears a PIN left in the Keychain by an earlier one")
    func reinstallClearsTheOldPIN() throws {
        let fresh = try #require(UserDefaults(suiteName: "AppLockTests-\(UUID().uuidString)"))
        let store = InMemoryPINStore(record: PINRecord(pin: "123456"))
        let lock = AppLock(store: store, biometrics: NoBiometrics(), defaults: fresh)
        #expect(lock.status == .noPIN)
        #expect(store.load() == nil)
    }

    @Test("Later launches of the same install keep the PIN")
    func relaunchKeepsThePIN() throws {
        let store = InMemoryPINStore()
        try lock(store).setInitialPIN("123456")
        let relaunched = lock(store)
        #expect(relaunched.status == .set)
        #expect(relaunched.verify("123456"))
    }

    @Test("A wipe that failed is retried at the next launch")
    func failedWipeIsRetried() throws {
        let fresh = try #require(UserDefaults(suiteName: "AppLockTests-\(UUID().uuidString)"))
        let store = FailingPINStore()
        store.record = PINRecord(pin: "123456")
        store.failsDelete = true
        _ = AppLock(store: store, biometrics: NoBiometrics(), defaults: fresh)
        #expect(store.record != nil)
        store.failsDelete = false
        let relaunched = AppLock(store: store, biometrics: NoBiometrics(), defaults: fresh)
        #expect(store.record == nil)
        #expect(relaunched.status == .noPIN)
    }
}

@MainActor
@Suite("PIN flows")
struct PINFlowModelTests {
    private func lock(pin: String? = nil) throws -> AppLock {
        let defaults = try #require(UserDefaults(suiteName: "PINFlowTests-\(UUID().uuidString)"))
        defaults.set(true, forKey: "security.pinInstallMarker")
        return AppLock(
            store: InMemoryPINStore(record: pin.map { PINRecord(pin: $0) }), biometrics: NoBiometrics(),
            defaults: defaults
        )
    }

    @Test("Setup asks twice and a mismatch starts the new PIN over")
    func setup() throws {
        let lock = try lock()
        let model = PINFlowModel(flow: .setup, lock: lock)
        #expect(model.step == .new)
        #expect(!model.enter("123456"))
        #expect(model.step == .confirm)
        #expect(!model.enter("111111"))
        #expect(model.step == .new)
        #expect(model.notice == .mismatch)
        #expect(lock.status == .noPIN)
        #expect(!model.enter("123456"))
        #expect(model.notice == nil)
        #expect(model.enter("123456"))
        #expect(lock.verify("123456"))
    }

    @Test("Unlock finishes on the right PIN only")
    func unlock() throws {
        let model = try PINFlowModel(flow: .unlock, lock: lock(pin: "123456"))
        #expect(!model.enter("000000"))
        #expect(model.notice == .wrongPIN)
        #expect(model.digits.isEmpty)
        #expect(model.enter("123456"))
    }

    @Test("Entry waits for six digits and ignores anything else")
    func entrySanitised() throws {
        let model = try PINFlowModel(flow: .unlock, lock: lock(pin: "123456"))
        #expect(!model.enter("12"))
        #expect(model.digits == "12")
        #expect(!model.enter("12a٣4"))
        #expect(model.digits == "124")
        #expect(model.enter("1234567"))
    }

    @Test("Change walks current, new, confirm and only writes at the end")
    func change() throws {
        let lock = try lock(pin: "123456")
        let model = PINFlowModel(flow: .change, lock: lock)
        #expect(!model.enter("000000"))
        #expect(model.step == .current)
        #expect(!model.enter("123456"))
        #expect(model.step == .new)
        #expect(!model.enter("654321"))
        #expect(lock.verify("123456"))
        #expect(model.enter("654321"))
        #expect(lock.verify("654321"))
    }

    @Test("Reset refuses a wrong PIN and removes the PIN on the right one")
    func reset() throws {
        let lock = try lock(pin: "123456")
        let model = PINFlowModel(flow: .reset, lock: lock)
        #expect(!model.enter("000000"))
        #expect(lock.status == .set)
        #expect(model.enter("123456"))
        #expect(lock.status == .noPIN)
    }
}

/// The real item. An unsigned test host, which is how CI builds, has no Keychain access at all
/// (`errSecMissingEntitlement`), so the suite only runs where the Keychain answers.
@MainActor
@Suite("Keychain PIN store", .enabled(if: KeychainAvailability.isAvailable))
struct KeychainPINStoreTests {
    @Test("Round trip, overwrite and delete")
    func roundTrip() throws {
        let store = KeychainPINStore(service: "id.laci.pin.test.\(UUID().uuidString)")
        defer { try? store.delete() }
        #expect(try store.load() == nil)
        let first = PINRecord(pin: "123456")
        try store.save(first)
        #expect(try store.load() == first)
        let second = PINRecord(pin: "654321")
        try store.save(second)
        #expect(try store.load() == second)
        try store.delete()
        #expect(try store.load() == nil)
        try store.delete()
    }
}

nonisolated enum KeychainAvailability {
    static var isAvailable: Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "id.laci.pin.test.probe",
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) != errSecMissingEntitlement
    }
}
