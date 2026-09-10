import Foundation
import LaciPrint
import Testing

@Suite("Transliteration")
struct CodepageTests {
    static let printable = UInt8(0x20) ... UInt8(0x7E)

    /// The names come from the seed catalogue, so the test gets harder when the real capture
    /// replaces the placeholder. The SPEC §7.2 examples are added because the placeholder is
    /// pure ASCII and would exercise nothing.
    static func names() throws -> [String] {
        let text = try String(contentsOf: warung200URL, encoding: .utf8)
        let rows = text.split(whereSeparator: \.isNewline).filter { !$0.hasPrefix("#") }.dropFirst()
        let names = rows.prefix(40).map { csvName(String($0)) }
        try #require(names.count == 40)
        return names + [
            "🍜🥤🧃 ✅ 😀 Es Teh Manis",
            "Susu Ultra 250ml ×12",
            "Kopi Kapal Api “Special” – 65g…",
            "Rp\u{00A0}15.000 → Rp 14.000 • Promo",
            "Croissant 1€ ★",
        ]
    }

    @Test("Forty real product names plus emoji and the SPEC's awkward cases encode to printable ASCII")
    func productNamesArePrintableASCII() throws {
        for name in try Self.names() {
            let bytes = Codepage.cp437.encode(name)
            #expect(!bytes.isEmpty, "\(name)")
            #expect(bytes.allSatisfy { Self.printable.contains($0) }, "\(name)")
            #expect(bytes.count == Codepage.cp437.transliterate(name).count, "\(name)")
        }
    }

    @Test("Folds map typographic characters to their ASCII stand-ins", arguments: [
        ("×", "x"), ("–", "-"), ("—", "-"), ("“", "\""), ("”", "\""), ("‘", "'"), ("’", "'"),
        ("…", "..."), ("→", "->"), ("•", "*"), ("€", "EUR"), ("\u{00A0}", " "),
    ])
    func folds(input: String, expected: String) {
        #expect(Codepage.cp437.transliterate(input) == expected)
    }

    @Test("Characters outside the page lose their marks or become a question mark", arguments: [
        ("ő", "o"), ("ș", "s"), ("Ａ", "A"), ("☃", "?"), ("😀", "?"), ("\u{01}", "?"), ("\n", "?"),
    ])
    func fallbacks(input: String, expected: String) {
        #expect(Codepage.cp437.transliterate(input) == expected)
    }

    @Test("Characters CP437 has are kept and encoded as the printer's own byte", arguments: [
        (" ", 0x20), ("~", 0x7E), ("Ç", 0x80), ("é", 0x82), ("ñ", 0xA4), ("½", 0xAB), ("²", 0xFD), ("■", 0xFE),
    ])
    func nativeGlyphs(input: String, byte: UInt8) {
        #expect(Codepage.cp437.transliterate(input) == input)
        #expect(Array(Codepage.cp437.encode(input)) == [byte])
    }
}

/// Second column of a catalogue row, unquoting `""`.
private func csvName(_ line: String) -> String {
    let afterSKU = line.drop { $0 != "," }.dropFirst()
    guard afterSKU.first == "\"" else {
        return String(afterSKU.prefix { $0 != "," })
    }
    var name = ""
    var rest = afterSKU.dropFirst()
    while let character = rest.first {
        rest = rest.dropFirst()
        if character == "\"" {
            guard rest.first == "\"" else { break }
            rest = rest.dropFirst()
        }
        name.append(character)
    }
    return name
}
