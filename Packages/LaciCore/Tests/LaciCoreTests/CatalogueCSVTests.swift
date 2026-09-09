import Foundation
import LaciCore
import Testing

@Suite("Catalogue CSV codec")
struct CatalogueCSVTests {
    static let header = "sku,name,unit,cost,price,tracks_stock,stock_on_hand,barcodes"

    static func row(
        _ sku: String, line: Int, name: String = "Indomie Goreng", barcodes: [String] = []
    ) throws -> CatalogueRow {
        try CatalogueRow(
            line: line, sku: sku, name: name, unit: "pcs", cost: 2500, price: 3000, tracksStock: true,
            stockOnHand: dec("10"), barcodes: barcodes
        )
    }

    @Test("Rows parse with quoted names, pipe-separated barcodes and physical line numbers")
    func parsesRows() throws {
        let text = """
        # category: warung sembako
        \(Self.header)
        SKU1,"Mie Sedaap Goreng ""Ayam Krispi"", 90g",pcs,2500,3000,true,10,5901234123457|96385074
        SKU2,Pulsa 10k,pcs,10000,12000,false,0,
        """
        let parsed = try CatalogueCSV.parse(text)
        #expect(parsed.rejected.isEmpty)
        #expect(parsed.rows.count == 2)
        let first = try #require(parsed.rows.first)
        #expect(first.line == 3)
        #expect(first.name == "Mie Sedaap Goreng \"Ayam Krispi\", 90g")
        #expect(first.barcodes == ["5901234123457", "96385074"])
        #expect(first.cost == 2500)
        #expect(first.stockOnHand == 10)
        let second = try #require(parsed.rows.last)
        #expect(second.line == 4)
        #expect(second.tracksStock == false)
        #expect(second.barcodes.isEmpty)
    }

    @Test("A header that is not the canonical column list is refused")
    func headerMismatch() {
        #expect(throws: CatalogueCSV.ParseError.headerMismatch(found: ["sku", "name"])) {
            try CatalogueCSV.parse("sku,name\nA,B\n")
        }
    }

    @Test("An empty file is refused")
    func emptyFile() {
        #expect(throws: CatalogueCSV.ParseError.emptyFile) { try CatalogueCSV.parse("\n# only a comment\n") }
    }

    @Test("A BOM, CRLF line endings, comments and blank lines are tolerated")
    func bomCRLFCommentsBlanks() throws {
        let text = "\u{FEFF}\(Self.header)\r\n# comment\r\n\r\nSKU1,Indomie,pcs,2500,3000,true,10,\r\n"
        let parsed = try CatalogueCSV.parse(text)
        #expect(parsed.rows.map(\.sku) == ["SKU1"])
        #expect(parsed.rows.first?.line == 4)
    }

    @Test("tracks_stock accepts true/false and 1/0", arguments: [
        ("true", true), ("false", false), ("1", true), ("0", false),
    ])
    func tracksStockSpellings(spelling: String, expected: Bool) throws {
        let parsed = try CatalogueCSV.parse("\(Self.header)\nS,N,pcs,1,2,\(spelling),0,\n")
        #expect(parsed.rows.first?.tracksStock == expected)
    }

    @Test("A malformed money field or column count rejects only that row, with its line")
    func malformedRows() throws {
        let text = """
        \(Self.header)
        OK,Indomie,pcs,2500,3000,true,10,
        BAD,Indomie,pcs,2500,abc,true,10,
        SHORT,Indomie,pcs
        """
        let parsed = try CatalogueCSV.parse(text)
        #expect(parsed.rows.map(\.sku) == ["OK"])
        #expect(parsed.rejected.map(\.line) == [3, 4])
        #expect(parsed.rejected.first?.sku == "BAD")
        for rejection in parsed.rejected {
            guard case .malformed = rejection.reason else {
                Issue.record("expected .malformed at line \(rejection.line)")
                continue
            }
        }
    }

    @Test("A SKU repeated in the file rejects every occurrence")
    func duplicateSKU() throws {
        let text = "\(Self.header)\nA,One,pcs,1,2,true,0,\nB,Two,pcs,1,2,true,0,\nA,Three,pcs,1,2,true,0,\n"
        let parsed = try CatalogueCSV.parse(text)
        #expect(parsed.rows.map(\.sku) == ["B"])
        #expect(parsed.rejected.map(\.line) == [2, 4])
        #expect(parsed.rejected.allSatisfy { $0.reason == .duplicateSKUInFile })
    }

    @Test("A barcode on two rows rejects both rows")
    func duplicateBarcode() throws {
        let text = "\(Self.header)\nA,One,pcs,1,2,true,0,5901234123457\nB,Two,pcs,1,2,true,0,5901234123457\n"
        let parsed = try CatalogueCSV.parse(text)
        #expect(parsed.rows.isEmpty)
        let expected = ImportRejection.Reason.barcodeDuplicatedInFile(value: "5901234123457")
        #expect(parsed.rejected.map(\.reason) == [expected, expected])
    }

    @Test("A digit-only barcode with a bad check digit rejects the row")
    func invalidBarcode() throws {
        let parsed = try CatalogueCSV.parse("\(Self.header)\nA,One,pcs,1,2,true,0,5901234123458\n")
        #expect(parsed.rows.isEmpty)
        #expect(parsed.rejected.first?.reason == .invalidBarcode(value: "5901234123458"))
    }

    @Test("A semicolon delimiter parses the same rows")
    func semicolon() throws {
        let text = "sku;name;unit;cost;price;tracks_stock;stock_on_hand;barcodes\nA;Susu, Bendera;pcs;1;2;true;0;\n"
        let parsed = try CatalogueCSV.parse(text, delimiter: ";")
        #expect(parsed.rows.first?.name == "Susu, Bendera")
    }

    @Test("An unterminated quote is a parse error naming the line")
    func unterminatedQuote() {
        #expect(throws: CatalogueCSV.ParseError.unterminatedQuote(line: 2)) {
            try CatalogueCSV.parse("\(Self.header)\nA,\"Open,pcs,1,2,true,0,\n")
        }
    }

    @Test("Export writes unformatted decimals, quotes only when needed and no BOM")
    func exportShape() throws {
        let rows = try [
            Self.row("A", line: 2, barcodes: ["5901234123457"]),
            Self.row("B", line: 3, name: "Kopi Kapal Api \"Special\", 65g"),
        ]
        let text = CatalogueCSV.export(rows)
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines[0] == Self.header)
        #expect(lines[1] == "A,Indomie Goreng,pcs,2500,3000,true,10,5901234123457")
        #expect(lines[2] == "B,\"Kopi Kapal Api \"\"Special\"\", 65g\",pcs,2500,3000,true,10,")
        #expect(text.unicodeScalars.first != "\u{FEFF}")
    }

    @Test("Export then parse round-trips every row")
    func roundTrip() throws {
        let rows = try [
            Self.row("A", line: 2, name: "Susu Bendera Coklat 115ml x 6", barcodes: ["5901234123457", "96385074"]),
            Self.row("B", line: 3, name: "Mie Sedaap Goreng \"Ayam Krispi\""),
        ]
        let parsed = try CatalogueCSV.parse(CatalogueCSV.export(rows, delimiter: ";"), delimiter: ";")
        #expect(parsed.rejected.isEmpty)
        #expect(parsed.rows == rows)
    }

    @Test("Symbology is inferred from length and check digit", arguments: [
        ("5901234123457", Symbology.ean13), ("96385074", .ean8), ("ABC-99", .code128), ("5901234123458", nil),
    ])
    func inferredSymbology(value: String, expected: Symbology?) {
        #expect(Symbology.inferred(from: value) == expected)
    }
}
