import Foundation
import LaciPrint
import Testing

/// Regenerated only by `scripts/regenerate-print-goldens.sh` (`LACI_REGENERATE_GOLDENS=1`).
@Suite("Diagnostic receipt goldens")
struct DiagnosticReceiptGoldenTests {
    @Test("The test print matches the checked-in bytes", arguments: [PaperWidth.mm58, .mm80])
    func matchesGolden(paper: PaperWidth) throws {
        let data = DiagnosticReceipt.render(paper: paper)
        let url = fixturesDirectory.appending(path: "diagnostic-\(paper.columns).bin")
        if ProcessInfo.processInfo.environment["LACI_REGENERATE_GOLDENS"] == "1" {
            try FileManager.default.createDirectory(at: fixturesDirectory, withIntermediateDirectories: true)
            try data.write(to: url)
            print("regenerated \(url.path) (\(data.count) bytes)")
            return
        }
        let golden = try Data(contentsOf: url)
        let firstDifference = Array(zip(data, golden)).firstIndex { $0 != $1 } ?? min(data.count, golden.count)
        #expect(
            data == golden,
            "first difference at byte \(firstDifference); rendered \(data.count), golden \(golden.count)"
        )
    }
}

@Suite("Diagnostic receipt layout")
struct DiagnosticReceiptTests {
    @Test("The ruler is exactly one paper width, so a wrong width setting is visible on paper",
          arguments: [PaperWidth.mm58, .mm80])
    func ruler(paper: PaperWidth) {
        let lines = receiptText(DiagnosticReceipt.render(paper: paper))
        let ruler = String((1 ... paper.columns).map { Character(String($0 % 10)) })
        #expect(lines.contains(ruler))
        #expect(lines.allSatisfy { $0.utf8.count <= paper.columns })
    }

    @Test("It is the same bytes every time: no clock, no counter")
    func deterministic() {
        #expect(DiagnosticReceipt.render(paper: .mm58) == DiagnosticReceipt.render(paper: .mm58))
    }

    @Test("It names itself, exercises a two-column row, and ends with a cut")
    func content() {
        let data = DiagnosticReceipt.render(paper: .mm58)
        let lines = receiptText(data)
        #expect(lines[0] == "LACI")
        #expect(lines[1] == "Tes cetak")
        #expect(lines.contains("Kiri                       Kanan"))
        #expect(lines.contains("Karakter: a x - \"kutip\" ... OK"))
        #expect(data.suffix(4) == Data([0x1D, 0x56, 0x42, 0x00]))
    }
}
