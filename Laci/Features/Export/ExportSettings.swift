import Foundation

/// SPEC §5.2: an Indonesian-locale Excel install splits on semicolons, so the delimiter is a
/// setting. Comma by default; the toggle is the only thing that changes it.
nonisolated enum ExportSettings {
    private static let semicolonKey = "export.semicolonDelimiter"

    static func semicolonDelimiter(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: semicolonKey)
    }

    static func save(semicolonDelimiter: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(semicolonDelimiter, forKey: semicolonKey)
    }

    static func delimiter(in defaults: UserDefaults = .standard) -> Character {
        semicolonDelimiter(in: defaults) ? ";" : ","
    }
}
