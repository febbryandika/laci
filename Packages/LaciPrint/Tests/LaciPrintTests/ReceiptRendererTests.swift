import Foundation
import LaciMoney
import LaciPrint
import Testing

/// Regenerated only by `scripts/regenerate-print-goldens.sh`, which sets `LACI_REGENERATE_GOLDENS=1`;
/// a plain test run never writes.
@Suite("Receipt renderer goldens")
struct ReceiptRendererGoldenTests {
    @Test("A representative receipt matches the checked-in bytes", arguments: [PaperWidth.mm58, .mm80])
    func matchesGolden(paper: PaperWidth) throws {
        let data = try ReceiptRenderer.render(sampleReceipt(), paper: paper)
        let url = fixturesDirectory.appending(path: "receipt-\(paper.columns).bin")
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

@Suite("Receipt layout")
struct ReceiptRendererTests {
    @Test("No text line is wider than the paper", arguments: [PaperWidth.mm58, .mm80])
    func fitsColumns(paper: PaperWidth) throws {
        let lines = try receiptText(ReceiptRenderer.render(sampleReceipt(), paper: paper))
        for line in lines {
            #expect(line.utf8.count <= paper.columns, "\(line)")
        }
    }

    @Test("Header, number, date, lines, totals, cash tender and footer appear in order")
    func cashReceipt() throws {
        let lines = try receiptText(ReceiptRenderer.render(sampleReceipt(), paper: .mm58))
        #expect(lines[0] == "Warung Bu Sari")
        #expect(lines[1] == "Jl. Melati No. 12, Bandung")
        #expect(lines[2] == "0812-3456-7890")
        #expect(lines[3] == String(repeating: "-", count: 32))
        #expect(lines[4] == "No. 42          10/09/2025 17.26")
        #expect(lines[6] == "Indomie Goreng 85g              ")
        #expect(lines[7] == "  2 bungkus x Rp 3.500  Rp 7.000")
        #expect(lines[8] == "Mie Sedaap Goreng \"Ayam Krispi. ")
        #expect(lines[11] == "  12 kotak x Rp 6.000  Rp 72.000")
        #expect(lines[12] == "  Diskon               -Rp 6.000")
        #expect(lines[14] == "  0,5 kg x Rp 18.000    Rp 9.000")
        #expect(lines[16] == "Subtotal               Rp 85.500")
        #expect(lines[17] == "Diskon                 -Rp 1.250")
        #expect(lines[18] == "Pembulatan                +Rp 50")
        #expect(lines[19] == "TOTAL                  Rp 84.300")
        #expect(lines[20] == "Tunai                 Rp 100.000")
        #expect(lines[21] == "Kembali                Rp 15.700")
        #expect(lines[23] == "Terima kasih")
        #expect(lines[24] == "Struk bukan faktur pajak")
        #expect(!lines.contains("*** CETAK ULANG ***"))
    }

    @Test("Non-cash tender prints the method and reference and no rounding line")
    func qrisReceipt() throws {
        let receipt = try sampleReceipt(
            tender: .qris(reference: "QR-20250910-001"), roundingDelta: .zero, total: Money(84250)
        )
        let lines = receiptText(ReceiptRenderer.render(receipt, paper: .mm58))
        #expect(lines.contains("QRIS             QR-20250910-001"))
        #expect(lines.contains("TOTAL                  Rp 84.250"))
        #expect(!lines.contains { $0.hasPrefix("Pembulatan") || $0.hasPrefix("Tunai") || $0.hasPrefix("Kembali") })
    }

    @Test("A transfer prints its reference")
    func transferReceipt() throws {
        let receipt = try sampleReceipt(
            tender: .transfer(reference: "BCA 1234"), roundingDelta: .zero, total: Money(84250)
        )
        let lines = receiptText(ReceiptRenderer.render(receipt, paper: .mm58))
        #expect(lines.contains("Transfer                BCA 1234"))
    }

    @Test("A negative rounding delta and a fractional total are formatted in id_ID")
    func negativeRoundingAndFraction() throws {
        let receipt = try sampleReceipt(roundingDelta: Money(-50), total: money("12350.5"))
        let lines = receiptText(ReceiptRenderer.render(receipt, paper: .mm58))
        #expect(lines.contains("Pembulatan                -Rp 50"))
        #expect(lines.contains("TOTAL                Rp 12.350,5"))
    }

    @Test("PPN prints only when there is tax, with the effective rate")
    func taxLine() throws {
        let taxed = try sampleReceipt(taxTotal: Money(9300), taxRate: dec("0.11"))
        #expect(receiptText(ReceiptRenderer.render(taxed, paper: .mm58)).contains("PPN 11%                 Rp 9.300"))
        let untaxed = try receiptText(ReceiptRenderer.render(sampleReceipt(), paper: .mm58))
        #expect(!untaxed.contains { $0.hasPrefix("PPN") })
    }

    @Test("A reprint is marked under the header")
    func reprintMarker() throws {
        let lines = try receiptText(ReceiptRenderer.render(sampleReceipt(isReprint: true), paper: .mm58))
        #expect(lines[3] == "*** CETAK ULANG ***")
    }

    @Test("A logo is emitted as a raster image right after initialisation and centring")
    func logo() throws {
        let data = try ReceiptRenderer.render(sampleReceipt(logo: sampleLogo16), paper: .mm58)
        let expectedPrefix: [UInt8] = [
            0x1B, 0x40, 0x1B, 0x74, 0x00, 0x1B, 0x61, 0x01, 0x1D, 0x76, 0x30, 0x00, 0x02, 0x00, 0x10, 0x00,
        ]
        #expect(Array(data.prefix(16 + 32)) == expectedPrefix + sampleLogo16Bytes)
    }

    @Test("Bold and double height wrap the shop name and bold wraps the total")
    func emphasis() throws {
        let data = try ReceiptRenderer.render(sampleReceipt(), paper: .mm58)
        let bytes = Array(data)
        let name = Array("Warung Bu Sari".utf8)
        let nameStart = try #require(bytes.firstRange(of: name)?.lowerBound)
        #expect(Array(bytes[nameStart - 6 ..< nameStart]) == [0x1B, 0x45, 0x01, 0x1D, 0x21, 0x01])
        let nameEnd = nameStart + name.count
        #expect(Array(bytes[nameEnd ..< nameEnd + 7]) == [0x0A, 0x1D, 0x21, 0x00, 0x1B, 0x45, 0x00])
        let total = Array("TOTAL ".utf8)
        let totalStart = try #require(bytes.firstRange(of: total)?.lowerBound)
        #expect(Array(bytes[totalStart - 3 ..< totalStart]) == [0x1B, 0x45, 0x01])
    }

    @Test("The stream ends with a partial cut")
    func endsWithCut() throws {
        let data = try ReceiptRenderer.render(sampleReceipt(), paper: .mm80)
        #expect(Array(data.suffix(7)) == [0x1B, 0x64, 0x03, 0x1D, 0x56, 0x42, 0x00])
    }
}
