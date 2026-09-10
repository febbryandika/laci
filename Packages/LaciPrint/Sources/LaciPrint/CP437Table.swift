import Foundation

extension Codepage {
    /// Printable ASCII (0x20–0x7E) plus the CP437 upper half (0x80–0xFE). Control bytes and 0x7F are
    /// left out because a printer executes them, and 0xFF (no-break space) is left out so the
    /// `folds` entry turns it into an ordinary space instead of a glyph the receipt cannot measure.
    static let cp437Table: [Character: UInt8] = {
        var table: [Character: UInt8] = [:]
        for byte in UInt8(0x20) ... UInt8(0x7E) {
            table[Character(UnicodeScalar(byte))] = byte
        }
        for (offset, character) in upperHalf.enumerated() {
            table[character] = UInt8(0x80 + offset)
        }
        return table
    }()

    /// 0x80 through 0xFE, in code-point order.
    private static let upperHalf: [Character] = Array(
        """
        ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒ\
        áíóúñÑªº¿⌐¬½¼¡«»░▒▓│┤╡╢╖╕╣║╗╝╜╛┐\
        └┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀\
        αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■
        """
    )
}
