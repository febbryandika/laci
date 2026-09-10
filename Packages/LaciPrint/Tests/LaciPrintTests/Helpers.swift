import Foundation
import LaciMoney
import LaciPrint
import Testing

/// `Decimal` float literals are not exact (`1.11` is 1.1100000000000002048), so every non-integer
/// value in these tests is built from a string.
func dec(_ text: String) throws -> Decimal {
    try #require(Decimal(string: text))
}

func money(_ text: String) throws -> Money {
    try Money(dec(text))
}

/// `Packages/LaciPrint/Tests/LaciPrintTests`, resolved from this file so `swift test` finds the
/// fixtures from any working directory and the golden regenerator can write back into the tree.
let testsDirectory = URL(filePath: #filePath).deletingLastPathComponent()
let fixturesDirectory = testsDirectory.appending(path: "Fixtures")
/// The app's seed catalogue (SPEC §12), read in place so the test tracks the real file when it lands.
let warung200URL = testsDirectory.appending(path: "../../../../Laci/Resources/Fixtures/warung-200.csv").standardized

let jakarta = TimeZone(identifier: "Asia/Jakarta")!

/// 2025-09-10 17:26 WIB.
let sampleDate = Date(timeIntervalSince1970: 1_757_500_000)

/// One representative sale: a 35-character name that must clip at 32 columns, a line discount, a
/// fractional quantity, a whole-sale discount, and a +Rp 50 cash rounding.
func sampleReceipt(
    tender: Receipt.Tender = .cash(tendered: Money(100_000), change: Money(15700)),
    roundingDelta: Money = Money(50),
    total: Money = Money(84300),
    taxTotal: Money = .zero,
    taxRate: Decimal? = nil,
    isReprint: Bool = false,
    logo: MonoBitmap? = nil
) throws -> Receipt {
    try Receipt(
        shopName: "Warung Bu Sari",
        shopLines: ["Jl. Melati No. 12, Bandung", "0812-3456-7890"],
        footerLines: ["Terima kasih", "Struk bukan faktur pajak"],
        number: 42,
        occurredAt: sampleDate,
        timeZone: jakarta,
        lines: [
            Receipt.Line(
                name: "Indomie Goreng 85g", quantity: 2, unit: "bungkus", unitPrice: Money(3500), discount: .zero
            ),
            Receipt.Line(
                name: "Mie Sedaap Goreng \"Ayam Krispi\" 90g", quantity: 1, unit: "bungkus",
                unitPrice: Money(3500), discount: .zero
            ),
            Receipt.Line(
                name: "Susu Ultra Full Cream 250ml", quantity: 12, unit: "kotak",
                unitPrice: Money(6000), discount: Money(6000)
            ),
            Receipt.Line(
                name: "Gula Pasir Gulaku 1kg", quantity: dec("0.5"), unit: "kg",
                unitPrice: Money(18000), discount: .zero
            ),
        ],
        subtotal: Money(85500),
        saleDiscount: Money(1250),
        taxTotal: taxTotal,
        taxRate: taxRate,
        roundingDelta: roundingDelta,
        total: total,
        tender: tender,
        isReprint: isReprint,
        logo: logo
    )
}

/// 16×16: a solid top and bottom row, a left and right border, and a diagonal. Packed by hand in
/// `sampleLogo16Bytes`.
let sampleLogo16: MonoBitmap = {
    var pixels = [Bool](repeating: false, count: 256)
    for index in 0 ..< 256 {
        let row = index / 16, column = index % 16
        pixels[index] = row == 0 || row == 15 || column == 0 || column == 15 || column == row
    }
    return MonoBitmap(width: 16, height: 16, pixels: pixels)
}()

let sampleLogo16Bytes: [UInt8] = [
    0xFF, 0xFF, // row 0: solid
    0xC0, 0x01, // row 1: columns 0, 1, 15
    0xA0, 0x01, // row 2: columns 0, 2, 15
    0x90, 0x01,
    0x88, 0x01,
    0x84, 0x01,
    0x82, 0x01,
    0x81, 0x01, // row 7: columns 0, 7, 15
    0x80, 0x81, // row 8: columns 0, 8, 15
    0x80, 0x41,
    0x80, 0x21,
    0x80, 0x11,
    0x80, 0x09,
    0x80, 0x05,
    0x80, 0x03, // row 14: columns 0, 14, 15
    0xFF, 0xFF, // row 15: solid
]

/// The printable text of an ESC/POS stream, one entry per LF, with every command sequence the
/// builder emits stripped out so a test can reason about columns.
func receiptText(_ data: Data) -> [String] {
    var text = [UInt8]()
    var index = data.startIndex
    while index < data.endIndex {
        let byte = data[index]
        switch byte {
        case 0x1B: // ESC @ is two bytes; ESC t/a/E/d carry one parameter
            index += data[index + 1] == 0x40 ? 2 : 3
        case 0x1D where data[index + 1] == 0x56: // GS V m 0
            index += 4
        case 0x1D where data[index + 1] == 0x76: // GS v 0 m xL xH yL yH + raster
            let widthBytes = Int(data[index + 4]) | Int(data[index + 5]) << 8
            let height = Int(data[index + 6]) | Int(data[index + 7]) << 8
            index += 8 + widthBytes * height
        case 0x1D: // GS ! n
            index += 3
        default:
            text.append(byte)
            index += 1
        }
    }
    // Byte-for-byte, not UTF-8: the stream is CP437 and every byte here is one column.
    return String(text.map { Character(UnicodeScalar($0)) })
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)
}
