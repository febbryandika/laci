import Foundation
import LaciPrint
import Testing

@Suite("ESC/POS commands")
struct ESCPOSCommandTests {
    @Test("initialize resets the printer and selects the code page")
    func initialize() {
        var builder = ESCPOSBuilder()
        builder.initialize()
        #expect(Array(builder.data) == [0x1B, 0x40, 0x1B, 0x74, 0x00])
    }

    @Test("Alignment, bold, double height and feed are the documented byte triples")
    func formatting() {
        var builder = ESCPOSBuilder()
        builder.align(.center)
        builder.align(.right)
        builder.bold(true)
        builder.bold(false)
        builder.doubleHeight(true)
        builder.doubleHeight(false)
        builder.feed(2)
        #expect(Array(builder.data) == [
            0x1B, 0x61, 0x01, 0x1B, 0x61, 0x02,
            0x1B, 0x45, 0x01, 0x1B, 0x45, 0x00,
            0x1D, 0x21, 0x01, 0x1D, 0x21, 0x00,
            0x1B, 0x64, 0x02,
        ])
    }

    @Test("Cut feeds three lines past the tear bar first")
    func cut() {
        var partial = ESCPOSBuilder()
        partial.cut()
        #expect(Array(partial.data) == [0x1B, 0x64, 0x03, 0x1D, 0x56, 0x42, 0x00])
        var full = ESCPOSBuilder()
        full.cut(.full)
        #expect(Array(full.data) == [0x1B, 0x64, 0x03, 0x1D, 0x56, 0x00, 0x00])
    }

    @Test("line encodes through the code page and ends with LF")
    func line() {
        var builder = ESCPOSBuilder()
        builder.line("Rp 5×2")
        #expect(Array(builder.data) == [0x52, 0x70, 0x20, 0x35, 0x78, 0x32, 0x0A])
    }

    @Test("rule spans exactly the column width", arguments: [32, 48])
    func rule(columns: Int) {
        var builder = ESCPOSBuilder(columns: columns)
        builder.rule()
        #expect(builder.data.count == columns + 1)
        #expect(builder.data.dropLast().allSatisfy { $0 == 0x2D })
    }

    @Test("image emits the GS v 0 header with little-endian sizes then the packed rows")
    func image() {
        var builder = ESCPOSBuilder()
        builder.image(sampleLogo16)
        #expect(Array(builder.data) == [0x1D, 0x76, 0x30, 0x00, 0x02, 0x00, 0x10, 0x00] + sampleLogo16Bytes)
    }
}

@Suite("row() width invariant")
struct ESCPOSRowTests {
    static let pairs: [(String, String)] = [
        ("", ""),
        ("Subtotal", "Rp 85.500"),
        ("Indomie Goreng 85g", "Rp 7.000"),
        (String(repeating: "Mie Sedaap Goreng ", count: 4), "Rp 3.500"), // 72 chars, must clip
        ("Susu Ultra 250ml ×12 – “Promo”…", "Rp 1.250.000"), // folds widen the left side
        ("Total", String(repeating: "9", count: 60)), // right side wider than the paper
        (String(repeating: "x", count: 31), "Rp 1"), // exact fit minus one
        (String(repeating: "x", count: 27), "Rp 1"), // no room for the gutter at 32
    ]

    struct Case: Sendable {
        let columns: Int, left: String, right: String
    }

    static var cases: [Case] {
        [32, 48].flatMap { columns in pairs.map { Case(columns: columns, left: $0.0, right: $0.1) } }
    }

    @Test("A row is always exactly `columns` bytes plus LF", arguments: cases)
    func rowNeverExceedsColumns(_ testCase: Case) {
        var builder = ESCPOSBuilder(columns: testCase.columns)
        builder.row(testCase.left, testCase.right)
        #expect(builder.data.count == testCase.columns + 1, "\(testCase.columns): \(testCase.left) | \(testCase.right)")
        #expect(builder.data.last == 0x0A)
    }

    @Test("A clipped left side ends in a dot and keeps a one-space gutter")
    func clipMarker() {
        var builder = ESCPOSBuilder(columns: 32)
        builder.row("Mie Sedaap Goreng \"Ayam Krispi\" 90g", "Rp 3.500")
        #expect(receiptText(builder.data).first == "Mie Sedaap Goreng \"Aya. Rp 3.500")
    }

    @Test("A short left side is padded so the right side ends on the last column")
    func padding() {
        var builder = ESCPOSBuilder(columns: 32)
        builder.row("TOTAL", "Rp 84.300")
        #expect(receiptText(builder.data).first == "TOTAL                  Rp 84.300")
    }
}
