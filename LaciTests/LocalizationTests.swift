import Foundation
@testable import Laci
import Testing

/// SPEC §9: id is the source, en and ja are complete, and counts follow the catalog's plural
/// rules. A key missing from en or ja would silently fall back to Indonesian on the device, so the
/// compiled tables are checked against the catalog, not against each other.
@MainActor
@Suite("String catalog")
struct LocalizationTests {
    static let catalogURL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "../Laci/Resources/Localizable.xcstrings")
        .standardized

    static func catalogKeys() throws -> Set<String> {
        let data = try Data(contentsOf: catalogURL)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(json["strings"] as? [String: Any])
        return Set(strings.keys)
    }

    /// Every key the compiled bundle can resolve in a language: plain strings plus plural ones.
    static func compiledKeys(_ language: String) throws -> Set<String> {
        var keys = Set<String>()
        for ext in ["strings", "stringsdict"] {
            guard let url = Bundle.main.url(
                forResource: "Localizable", withExtension: ext, subdirectory: nil, localization: language
            ) else { continue }
            let table = try #require(NSDictionary(contentsOf: url) as? [String: Any])
            keys.formUnion(table.keys)
        }
        return keys
    }

    @Test("The catalog's source language is Indonesian and nothing is stale")
    func sourceLanguage() throws {
        let data = try Data(contentsOf: Self.catalogURL)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["sourceLanguage"] as? String == "id")
        let strings = try #require(json["strings"] as? [String: [String: Any]])
        let stale = strings.filter { $0.value["extractionState"] as? String == "stale" }.keys
        #expect(stale.isEmpty, "\(stale.sorted())")
    }

    @Test("Every key has an en and a ja translation in the built app", arguments: ["en", "ja"])
    func complete(language: String) throws {
        let expected = try Self.catalogKeys()
        let compiled = try Self.compiledKeys(language)
        #expect(!expected.isEmpty)
        let untranslated = expected.subtracting(compiled).sorted()
        #expect(untranslated.isEmpty, "untranslated in \(language): \(untranslated)")
        #expect(compiled.subtracting(expected).isEmpty, "not in catalog: \(compiled.subtracting(expected).sorted())")
    }

    @Test("Every translation is marked translated, none left new")
    func statesAreTranslated() throws {
        let data = try Data(contentsOf: Self.catalogURL)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(json["strings"] as? [String: [String: Any]])
        var notTranslated: [String] = []
        for (key, entry) in strings {
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            for language in ["en", "ja"] {
                guard let localization = localizations[language] else {
                    notTranslated.append("\(language): \(key)")
                    continue
                }
                let text = String(describing: localization)
                if text.contains("\"new\"") || text.contains("needs_review") {
                    notTranslated.append("\(language): \(key)")
                }
            }
        }
        #expect(notTranslated.isEmpty, "\(notTranslated.sorted())")
    }

    @Test("Counts follow the catalog's plural rules: one form in id and ja, two in en", arguments: [
        (1, "id", "1 SKU disesuaikan."), (2, "id", "2 SKU disesuaikan."),
        (1, "en", "1 SKU adjusted."), (2, "en", "2 SKUs adjusted."), (0, "en", "0 SKUs adjusted."),
        (1, "ja", "1件のSKUを調整しました。"), (2, "ja", "2件のSKUを調整しました。"),
    ])
    func plural(count: Int, language: String, expected: String) {
        #expect(localized("\(count) SKU disesuaikan.", in: language) == expected)
    }

    @Test("A sentence with two counts varies by the one that carries the noun", arguments: [
        (0, 1, "en", "0 of 1 sale"), (3, 30, "en", "3 of 30 sales"),
        (3, 30, "id", "3 dari 30 penjualan"), (3, 30, "ja", "30件中3件の売上"),
    ])
    func twoCounts(sold: Int, limit: Int, language: String, expected: String) {
        #expect(localized("\(sold) dari \(limit) penjualan", in: language) == expected)
    }

    @Test("Two counts in one sentence keep their order per language", arguments: [
        (1, 2, "en", "1 added, 2 updated."), (1, 2, "ja", "1件追加、2件更新。"), (1, 2, "id", "1 ditambah, 2 diperbarui."),
    ])
    func addedUpdated(added: Int, updated: Int, language: String, expected: String) {
        #expect(localized("\(added) ditambah, \(updated) diperbarui.", in: language) == expected)
    }

    @Test("The MTU byte count and the trial sentences vary by plural in English")
    func englishPlurals() {
        let cases: [(LocalizedStringResource, String)] = [
            ("\(1) byte", "1 byte"), ("\(244) byte", "244 bytes"),
            ("Terapkan \(1) penyesuaian stok?", "Apply 1 stock adjustment?"),
            ("Terapkan \(4) penyesuaian stok?", "Apply 4 stock adjustments?"),
            ("Laci gratis untuk \(30) penjualan pertama.", "Laci is free for the first 30 sales."),
            ("Baris punya \(1) kolom, seharusnya \(8)", "Row has 1 column, expected 8"),
            ("Baris punya \(3) kolom, seharusnya \(8)", "Row has 3 columns, expected 8"),
        ]
        for (resource, expected) in cases {
            #expect(localized(resource, in: "en") == expected)
        }
    }

    @Test("The usage descriptions are localized for the permission alerts", arguments: ["id", "en", "ja"])
    func usageDescriptions(language: String) throws {
        let url = try #require(Bundle.main.url(
            forResource: "InfoPlist", withExtension: "strings", subdirectory: nil, localization: language
        ))
        let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
        #expect(table["NSCameraUsageDescription"]?.isEmpty == false)
        #expect(table["NSBluetoothAlwaysUsageDescription"]?.isEmpty == false)
    }

    @Test("Money in a sentence is the shop's format whatever the UI language")
    func moneyInSentenceStaysIndonesian() {
        let amount = Decimal(15000).formatted(MoneyFormat.rupiah)
        let english = localized("Uang kurang dari \(amount)", in: "en")
        #expect(english == "Cash is less than \(amount)")
        #expect(english.contains("15.000"))
        #expect(MoneyFormat.spoken.format(15000).hasPrefix("15.000"))
    }
}
