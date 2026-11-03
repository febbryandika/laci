import Foundation
import Observation
import os

enum AppLockError: Error, Hashable {
    case wrongPIN
    case invalidFormat
    case storeFailed
}

/// The whole permissions model (SPEC §15): one owner PIN in front of the screens that show margins
/// or change the shop. Selling never comes through here. Every operation that replaces or removes
/// the PIN takes the current one, so the API has no way around it.
@MainActor
@Observable
final class AppLock {
    enum Status: Hashable {
        case noPIN
        case set
        /// The Keychain answered with an error. Not `noPIN`: that would let anyone set a new PIN
        /// over the owner's. Export stays reachable from the lock screen in this state too.
        case unreadable
    }

    private static let installMarkerKey = "security.pinInstallMarker"

    private(set) var status: Status
    /// False only for a UI test that did not ask for the lock. Release is always true.
    let isEnforced: Bool
    private let store: any PINStoring
    private let biometrics: any BiometricAuthenticating
    private let log = Log.store

    init(
        store: any PINStoring = KeychainPINStore(), biometrics: any BiometricAuthenticating = SystemBiometrics(),
        isEnforced: Bool = true, defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.biometrics = biometrics
        self.isEnforced = isEnforced
        Self.clearPINFromAnEarlierInstall(store: store, defaults: defaults)
        status = Self.currentStatus(of: store)
    }

    /// Keychain items outlive the app, `UserDefaults` does not. Without this, an owner who forgot
    /// the PIN, exported and reinstalled would meet the same forgotten PIN on an empty app.
    private static func clearPINFromAnEarlierInstall(store: any PINStoring, defaults: UserDefaults) {
        guard !defaults.bool(forKey: installMarkerKey) else { return }
        do {
            try store.delete()
            defaults.set(true, forKey: installMarkerKey)
        } catch {
            Log.store.error("pin marker not set: \(String(describing: error), privacy: .public)")
        }
    }

    private static func currentStatus(of store: any PINStoring) -> Status {
        do {
            return try store.load() == nil ? .noPIN : .set
        } catch {
            Log.store.error("pin unreadable: \(String(describing: error), privacy: .public)")
            return .unreadable
        }
    }

    var biometricKind: BiometricKind {
        biometrics.kind()
    }

    func authenticateWithBiometrics() async -> Bool {
        await biometrics.authenticate()
    }

    func verify(_ pin: String) -> Bool {
        guard let record = try? store.load() else { return false }
        return record.matches(pin)
    }

    /// The first PIN only. Refused while one exists or cannot be read.
    func setInitialPIN(_ pin: String) throws {
        guard status == .noPIN else { throw AppLockError.storeFailed }
        try write(pin)
        status = .set
        log.notice("pin set")
    }

    func change(currentPIN: String, to newPIN: String) throws {
        guard verify(currentPIN) else { throw AppLockError.wrongPIN }
        try write(newPIN)
        log.notice("pin changed")
    }

    /// Removes the PIN; the next owner screen asks for a new one.
    func reset(currentPIN: String) throws {
        guard verify(currentPIN) else { throw AppLockError.wrongPIN }
        do {
            try store.delete()
        } catch {
            throw AppLockError.storeFailed
        }
        status = .noPIN
        log.notice("pin reset")
    }

    private func write(_ pin: String) throws {
        guard PINRecord.isValid(pin) else { throw AppLockError.invalidFormat }
        do {
            try store.save(PINRecord(pin: pin))
        } catch {
            throw AppLockError.storeFailed
        }
    }
}
