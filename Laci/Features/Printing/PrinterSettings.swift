import Foundation
import LaciPrint

/// The printer pairing and paper width, in `UserDefaults` (SPEC §7.3). Paper width outlives the
/// pairing: the shop keeps its 80 mm rolls when it swaps the printer.
nonisolated enum PrinterSettings {
    private static let peripheralKey = "printer.peripheralID"
    private static let serviceKey = "printer.serviceUUID"
    private static let nameKey = "printer.name"
    private static let paperKey = "printer.paperWidth"

    static func remembered(in defaults: UserDefaults = .standard) -> RememberedPrinter? {
        guard let id = defaults.string(forKey: peripheralKey).flatMap(UUID.init(uuidString:)),
              let service = defaults.string(forKey: serviceKey) else { return nil }
        return RememberedPrinter(peripheralID: id, serviceUUID: service, name: defaults.string(forKey: nameKey) ?? "")
    }

    static func save(_ printer: RememberedPrinter, in defaults: UserDefaults = .standard) {
        defaults.set(printer.peripheralID.uuidString, forKey: peripheralKey)
        defaults.set(printer.serviceUUID, forKey: serviceKey)
        defaults.set(printer.name, forKey: nameKey)
    }

    static func forget(in defaults: UserDefaults = .standard) {
        for key in [peripheralKey, serviceKey, nameKey] {
            defaults.removeObject(forKey: key)
        }
    }

    /// 58 mm until told otherwise: it is what the cheapest printers take (SPEC §12).
    static func paperWidth(in defaults: UserDefaults = .standard) -> PaperWidth {
        defaults.string(forKey: paperKey) == "80" ? .mm80 : .mm58
    }

    static func save(paperWidth: PaperWidth, in defaults: UserDefaults = .standard) {
        defaults.set(paperWidth == .mm80 ? "80" : "58", forKey: paperKey)
    }
}
