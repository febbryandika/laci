import Foundation

/// The debug language override (SPEC §9 verification): the same `AppleLanguages` default the UI
/// tests set through a launch argument, written so a tester can see every language on one iPad
/// without touching iOS Settings. Read at launch, so a change needs a relaunch.
nonisolated enum LanguageSettings {
    enum Language: String, CaseIterable, Identifiable {
        case indonesian = "id"
        case english = "en"
        case japanese = "ja"

        var id: String {
            rawValue
        }
    }

    static let key = "AppleLanguages"

    /// The override in force, or nil when the device language decides. Read from the app's own
    /// domain only: a plain lookup falls through to the global domain and returns the device's
    /// languages, which would show an English iPad as overridden.
    static func override(
        in defaults: UserDefaults = .standard, domain: String = Bundle.main.bundleIdentifier ?? "id.Laci"
    ) -> Language? {
        guard let languages = defaults.persistentDomain(forName: domain)?[key] as? [String],
              let first = languages.first
        else { return nil }
        // "ja-JP" and "ja" both mean Japanese; the override only ever writes the bare code.
        return Language(rawValue: String(first.prefix { $0 != "-" }))
    }

    static func save(_ language: Language?, in defaults: UserDefaults = .standard) {
        if let language {
            defaults.set([language.rawValue], forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
