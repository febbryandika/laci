import Foundation
@testable import Laci
import Testing

@Suite("Language override")
struct LanguageSettingsTests {
    let defaults: UserDefaults
    let suite = "LanguageSettingsTests.\(UUID().uuidString)"

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("No override until one is saved, then the bare language code is what AppleLanguages holds")
    func saveAndRead() {
        #expect(LanguageSettings.override(in: defaults, domain: suite) == nil)
        LanguageSettings.save(.japanese, in: defaults)
        #expect(LanguageSettings.override(in: defaults, domain: suite) == .japanese)
        #expect(defaults.array(forKey: LanguageSettings.key) as? [String] == ["ja"])
        LanguageSettings.save(nil, in: defaults)
        #expect(LanguageSettings.override(in: defaults, domain: suite) == nil)
        #expect(defaults.persistentDomain(forName: suite)?[LanguageSettings.key] == nil)
    }

    @Test("A region-qualified code the system wrote still reads as its language", arguments: [
        (["id-ID"], LanguageSettings.Language.indonesian), (["en-GB", "id"], .english), (["fr"], nil),
    ])
    func regionQualified(stored: [String], expected: LanguageSettings.Language?) {
        defaults.set(stored, forKey: LanguageSettings.key)
        #expect(LanguageSettings.override(in: defaults, domain: suite) == expected)
    }
}
