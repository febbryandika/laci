import Foundation

/// The last print job, kept across launches (SPEC §14): by the time a shop owner sends a WhatsApp
/// about the printer, the app has usually been restarted, and an in-memory result is gone.
nonisolated struct PrintRecord: Codable, Hashable, Sendable {
    let outcome: PrintOutcome
    let duration: Duration?
    let printedAt: Date
}

nonisolated enum PrintRecordSettings {
    private static let key = "print.lastRecord"

    static func last(in defaults: UserDefaults = .standard) -> PrintRecord? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(PrintRecord.self, from: $0) }
    }

    static func save(_ record: PrintRecord, in defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key)
    }
}
