import Foundation
@testable import Laci
import Testing

@Suite("CSV export document")
struct CSVExportDocumentTests {
    @Test("The file starts with the UTF-8 BOM and the text follows it byte for byte")
    func bomIsFirstThreeBytes() {
        let document = CSVExportDocument(text: "sku,name\nA,Kopi \"Special\"\n")
        let data = document.fileData
        #expect(Array(data.prefix(3)) == [0xEF, 0xBB, 0xBF])
        #expect(String(bytes: data.dropFirst(3), encoding: .utf8) == document.text)
        #expect(data.count == 3 + document.text.utf8.count)
    }

    @Test("Reading a file back strips the BOM and keeps the text; a BOM-less file reads too")
    func readStripsBom() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("a,b\n".utf8))
        let read = try #require(CSVExportDocument(fileData: data))
        #expect(read.text == "a,b\n")
        let plain = try #require(CSVExportDocument(fileData: Data("a,b\n".utf8)))
        #expect(plain.text == "a,b\n")
        #expect(CSVExportDocument(fileData: Data([0xFF, 0xFE, 0x00])) == nil)
    }

    @Test("Writing then reading round-trips the text")
    func roundTrip() throws {
        let document = CSVExportDocument(text: "x;y\n1;\"a;b\"\n")
        let read = try #require(CSVExportDocument(fileData: document.fileData))
        #expect(read.text == document.text)
    }
}
