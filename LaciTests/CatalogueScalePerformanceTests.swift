import Foundation
@testable import Laci
import LaciCore
import XCTest

/// SPEC §11: the 200-SKU fixture scaled ×20, measured on the paths a shop at that size would feel —
/// the import, the scan-to-cart path the `scan-to-cart` signpost wraps, and loading and searching
/// the catalogue on the sell screen. XCTest because `measure` is XCTest's; no baselines are set,
/// so the numbers are reported, not asserted (a baseline would be per-device, inside the project).
final class CatalogueScalePerformanceTests: XCTestCase {
    private static let copies = 20

    /// The fixture's rows, copied `copies` times with suffixed SKUs and fresh EAN-13s in the
    /// in-store `29` range, so every copy passes the checksum gate and no barcode collides.
    @MainActor
    private func scaledRows() throws -> [CatalogueRow] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "warung-200", withExtension: "csv"))
        let parsed = try CatalogueCSV.parse(String(contentsOf: url, encoding: .utf8))
        XCTAssertEqual(parsed.rows.count, 200)
        return (1 ... Self.copies).flatMap { copy in
            parsed.rows.enumerated().map { index, row in
                CatalogueRow(
                    line: row.line, sku: String(format: "%@-%02d", row.sku, copy),
                    name: row.name, unit: row.unit, cost: row.cost, price: row.price, tracksStock: row.tracksStock,
                    stockOnHand: row.stockOnHand,
                    barcodes: row.barcodes.indices.map { Self.ean13(copy: copy, row: index, barcode: $0) }
                )
            }
        }
    }

    private static func ean13(copy: Int, row: Int, barcode: Int) -> String {
        let body = String(format: "29%02d%04d%d000", copy, row, barcode)
        let sum = body.compactMap(\.wholeNumberValue).reversed().enumerated().reduce(0) { total, pair in
            total + pair.element * (pair.offset.isMultiple(of: 2) ? 3 : 1)
        }
        return body + String((10 - sum % 10) % 10)
    }

    @MainActor
    private func importScaled(_ rows: [CatalogueRow], into dependencies: Dependencies) throws {
        let importer = CatalogueImporter(
            products: dependencies.products, transactor: dependencies.transactor
        )
        let preview = try importer.preview(CatalogueCSV.Parsed(rows: rows, rejected: []))
        XCTAssertEqual(preview.rejected, [])
        try importer.commit(preview, now: Date(timeIntervalSince1970: 1_800_000_000))
    }

    @MainActor
    private func seededCatalogue() throws -> (Dependencies, [CatalogueRow]) {
        let rows = try scaledRows()
        let dependencies = try Dependencies.inMemory()
        try importScaled(rows, into: dependencies)
        XCTAssertEqual(try dependencies.products.all(includeArchived: false).count, 200 * Self.copies)
        return (dependencies, rows)
    }

    private var manual: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        return options
    }

    /// Preview plus commit of 4,000 rows into an empty store; the store itself is built unmeasured.
    @MainActor
    func testImportAtScale() throws {
        let rows = try scaledRows()
        let options = manual
        options.iterationCount = 3
        measure(metrics: [XCTClockMetric()], options: options) {
            do {
                let dependencies = try Dependencies.inMemory()
                startMeasuring()
                try importScaled(rows, into: dependencies)
                stopMeasuring()
            } catch {
                XCTFail("import failed: \(error)")
            }
        }
    }

    /// 200 reads through `SellViewModel.didRead`, the camera's and the wedge's single entry point,
    /// against 4,000 SKUs. Seeded, so every run scans the same codes.
    @MainActor
    func testScanToCartAtScale() throws {
        let (dependencies, rows) = try seededCatalogue()
        var generator = SeededGenerator(state: 0x9E37_79B9)
        let codes = (0 ..< 200).compactMap { _ in rows.randomElement(using: &generator)?.barcodes.first }
        measure(metrics: [XCTClockMetric()], options: manual) {
            let viewModel = SellViewModel(dependencies: dependencies)
            startMeasuring()
            for code in codes {
                viewModel.didRead(code: code, symbology: .ean13)
            }
            stopMeasuring()
            XCTAssertEqual(viewModel.scansAccepted, codes.count)
        }
    }

    /// The sell screen's catalogue load and its in-memory search, for five typical queries.
    @MainActor
    func testCatalogueLoadAndSearchAtScale() throws {
        let (dependencies, _) = try seededCatalogue()
        measure(metrics: [XCTClockMetric()], options: manual) {
            let viewModel = SellViewModel(dependencies: dependencies)
            startMeasuring()
            viewModel.loadCatalogue()
            var matches = 0
            for query in ["indomie", "kopi", "W1", "susu", "85g"] {
                viewModel.query = query
                matches += viewModel.results.count
            }
            stopMeasuring()
            XCTAssertGreaterThan(matches, 0)
        }
    }
}

/// A deterministic generator for picking scan codes: xorshift, as in the money property tests.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
