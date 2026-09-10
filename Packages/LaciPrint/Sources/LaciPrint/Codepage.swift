import Foundation

/// ESC/POS printers speak a selected code page, not UTF-8 (SPEC §7.2). Indonesian orthography is
/// plain ASCII, but product names typed by a shop owner are not: `Susu Ultra 250ml ×12`,
/// `Kopi Kapal Api “Special”`, an emoji pasted out of WhatsApp.
public struct Codepage: Sendable {
    public let escposIndex: UInt8
    private let table: [Character: UInt8]

    public static let cp437 = Codepage(escposIndex: 0, table: Codepage.cp437Table)

    init(escposIndex: UInt8, table: [Character: UInt8]) {
        self.escposIndex = escposIndex
        self.table = table
    }

    /// Fold to something the printer can render; anything unmapped becomes '?'. The result is one
    /// byte per `Character` once encoded, which is what lets `ESCPOSBuilder.row` measure it.
    public func transliterate(_ text: String) -> String {
        var out = String()
        out.reserveCapacity(text.count)
        for character in text {
            out += fold(character)
        }
        return out
    }

    public func encode(_ text: String) -> Data {
        Data(transliterate(text).map { table[$0] ?? 0x3F })
    }

    private func fold(_ character: Character) -> String {
        if table[character] != nil {
            return String(character)
        }
        if let folded = Codepage.folds[character] {
            return folded
        }
        // Decompose and drop combining marks: "ő" → "o", "ș" → "s". A character the code page
        // already has ("é" in CP437) never reaches this branch: it is kept and printed as the
        // printer's own glyph.
        let stripped = String(character).folding(
            options: [.diacriticInsensitive, .widthInsensitive],
            locale: Codepage.foldingLocale
        )
        return stripped.allSatisfy { table[$0] != nil } ? stripped : "?"
    }

    private static let foldingLocale = Locale(identifier: "en_US")

    static let folds: [Character: String] = [
        "×": "x", "–": "-", "—": "-", "“": "\"", "”": "\"", "‘": "'", "’": "'",
        "…": "...", "→": "->", "•": "*", "€": "EUR", "\u{00A0}": " ",
    ]
}
