import Foundation

/// Whether the sell screen keeps a hidden field focused for a Bluetooth scanner that pretends to
/// be a keyboard (SPEC §6). Off by default: on a device with no hardware keyboard attached, that
/// focus would keep the software keyboard on the sell screen.
nonisolated enum ScannerSettings {
    private static let wedgeKey = "scanner.wedgeEnabled"

    static func wedgeEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: wedgeKey)
    }

    static func save(wedgeEnabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(wedgeEnabled, forKey: wedgeKey)
    }
}
