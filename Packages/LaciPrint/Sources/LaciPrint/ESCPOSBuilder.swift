import Foundation

/// Appends ESC/POS commands to `data` (SPEC §7.1). Every string goes through the `Codepage`, so
/// nothing the printer cannot render ever reaches the wire.
public struct ESCPOSBuilder: Sendable {
    public enum Align: UInt8, Sendable {
        case left = 0
        case center = 1
        case right = 2
    }

    public enum Cut: Sendable {
        case full
        case partial
    }

    public private(set) var data = Data()
    private let codepage: Codepage
    /// 32 on 58mm paper, 48 on 80mm.
    public let columns: Int

    public init(codepage: Codepage = .cp437, columns: Int = 32) {
        self.codepage = codepage
        self.columns = columns
    }

    public mutating func initialize() {
        data.append(contentsOf: [0x1B, 0x40]) // ESC @
        data.append(contentsOf: [0x1B, 0x74, codepage.escposIndex]) // ESC t n
    }

    public mutating func align(_ alignment: Align) {
        data.append(contentsOf: [0x1B, 0x61, alignment.rawValue])
    }

    public mutating func bold(_ isOn: Bool) {
        data.append(contentsOf: [0x1B, 0x45, isOn ? 1 : 0])
    }

    public mutating func doubleHeight(_ isOn: Bool) {
        data.append(contentsOf: [0x1D, 0x21, isOn ? 0x01 : 0x00]) // GS ! n
    }

    public mutating func feed(_ lines: UInt8) {
        data.append(contentsOf: [0x1B, 0x64, lines])
    }

    public mutating func cut(_ kind: Cut = .partial) {
        feed(3) // clear the tear bar first
        data.append(contentsOf: [0x1D, 0x56, kind == .full ? 0x00 : 0x42, 0x00])
    }

    public mutating func line(_ text: String = "") {
        data.append(codepage.encode(text))
        data.append(0x0A)
    }

    /// Two columns, amount right-aligned. The whole receipt is built from this one function, and it
    /// never emits more than `columns` characters: the right side is capped so a dot and a gutter
    /// always fit, and the left side is clipped to a trailing "." when it would push past the edge.
    public mutating func row(_ left: String, _ right: String) {
        // Transliterate BEFORE measuring: a character that folds to two ASCII characters changes
        // the column arithmetic, and a row one column too wide wraps and destroys the alignment
        // of every line after it.
        let rightText = String(codepage.transliterate(right).prefix(max(0, columns - 2)))
        let leftText = codepage.transliterate(left)
        let budget = columns - rightText.count
        let clipped = leftText.count + 1 > budget ? String(leftText.prefix(budget - 2)) + "." : leftText
        line(clipped + String(repeating: " ", count: budget - clipped.count) + rightText)
    }

    public mutating func rule(_ character: Character = "-") {
        line(String(repeating: String(character), count: columns))
    }

    /// GS v 0 — raster bitmap. 1 bit per pixel, MSB first, 1 = black.
    public mutating func image(_ bitmap: MonoBitmap) {
        let widthBytes = bitmap.bytesPerRow
        precondition(widthBytes <= 0xFFFF && bitmap.height <= 0xFFFF)
        data.append(contentsOf: [0x1D, 0x76, 0x30, 0x00])
        data.append(contentsOf: [UInt8(widthBytes & 0xFF), UInt8(widthBytes >> 8)])
        data.append(contentsOf: [UInt8(bitmap.height & 0xFF), UInt8(bitmap.height >> 8)])
        data.append(bitmap.packedRows)
    }
}
