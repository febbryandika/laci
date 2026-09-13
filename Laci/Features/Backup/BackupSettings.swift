import Foundation

/// The backup opt-in and the last successful backup instant (SPEC §5.3, §14).
nonisolated enum BackupSettings {
    private static let automaticKey = "backup.automaticEnabled"
    private static let lastBackupKey = "backup.lastBackupAt"

    static func automaticEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: automaticKey)
    }

    static func save(automaticEnabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(automaticEnabled, forKey: automaticKey)
    }

    static func lastBackupAt(in defaults: UserDefaults = .standard) -> Date? {
        guard defaults.object(forKey: lastBackupKey) != nil else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: lastBackupKey))
    }

    static func save(lastBackupAt date: Date, in defaults: UserDefaults = .standard) {
        defaults.set(date.timeIntervalSince1970, forKey: lastBackupKey)
    }
}
