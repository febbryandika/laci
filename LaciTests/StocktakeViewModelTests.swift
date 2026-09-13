import Foundation
@testable import Laci
import LaciCore
import LaciMoney
import SwiftData
import Testing

private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
private let barcodeA = "5901234123457"
private let misread = "5901234123458"
private let unknownEAN = "8992761111083"

@MainActor
@Suite("Stocktake view model")
struct StocktakeViewModelTests {
    let dependencies: Dependencies
    let viewModel: StocktakeViewModel

    init() throws {
        dependencies = try Dependencies.inMemory()
        viewModel = StocktakeViewModel(dependencies: dependencies, now: { fixedNow })
        try seed("A", stock: 10, cost: 1000)
        try seed("B", stock: 5, cost: 2500)
        try seed("C", stock: 8, cost: 700)
        try seed("U", stock: 0, cost: 0, tracksStock: false)
        try dependencies.products.addBarcode(barcodeA, symbology: .ean13, to: "A")
    }

    func seed(_ sku: String, stock: Decimal, cost: Decimal, tracksStock: Bool = true) throws {
        try dependencies.products.create(Product(
            sku: sku, name: "Item \(sku)", unit: "pcs", cost: cost, price: cost * 2, tracksStock: tracksStock,
            stockOnHand: stock, updatedAt: fixedNow
        ))
    }

    func movements() throws -> [StockMovement] {
        try dependencies.container.mainContext.fetch(FetchDescriptor<StockMovement>())
    }

    @Test("The first scan lists the SKU counted once with the system figure and cost")
    func firstScanAddsRowCountedOne() {
        viewModel.didRead(code: barcodeA, symbology: .ean13)
        #expect(viewModel.rows.map(\.sku) == ["A"])
        #expect(viewModel.rows.first?.countedText == "1")
        #expect(viewModel.rows.first?.systemQuantity == 10)
        #expect(viewModel.rows.first?.cost == Money(1000))
        #expect(viewModel.rows.first?.variance == -9)
        #expect(viewModel.scansAccepted == 1)
        #expect(viewModel.scanNotice == nil)
    }

    @Test("A repeat scan counts one more on the same row")
    func repeatScanIncrements() {
        viewModel.didRead(code: barcodeA, symbology: .ean13)
        viewModel.didRead(code: barcodeA, symbology: .ean13)
        viewModel.didRead(code: barcodeA, symbology: nil)
        #expect(viewModel.rows.count == 1)
        #expect(viewModel.rows.first?.countedText == "3")
        #expect(viewModel.scansAccepted == 3)
    }

    @Test("A typed SKU that is not a barcode still finds the product")
    func typedSKUFallsBackToProductLookup() {
        viewModel.didRead(code: " B ", symbology: nil)
        #expect(viewModel.rows.map(\.sku) == ["B"])
        #expect(viewModel.scanNotice == nil)
    }

    @Test("An unknown code is a notice, not a new product form")
    func unknownCodeShowsNoticeAndNoRow() {
        viewModel.didRead(code: unknownEAN, symbology: nil)
        #expect(viewModel.rows.isEmpty)
        #expect(viewModel.scanNotice == .unknownProduct)
        #expect(viewModel.scansAccepted == 0)
    }

    @Test("A bad checksum says scan again")
    func badChecksum() {
        viewModel.didRead(code: misread, symbology: .ean13)
        #expect(viewModel.rows.isEmpty)
        #expect(viewModel.scanNotice == .scanAgain)
    }

    @Test("A product that does not track stock cannot be counted")
    func untrackedProductRejected() {
        viewModel.didRead(code: "U", symbology: nil)
        #expect(viewModel.rows.isEmpty)
        #expect(viewModel.scanNotice == .untrackedProduct)
    }

    @Test("Editing the count moves the variance and its value at cost")
    func editedCountChangesVariance() throws {
        viewModel.didRead(code: "A", symbology: nil)
        viewModel.setCounted("7", for: "A")
        let row = try #require(viewModel.rows.first)
        #expect(row.counted == 7)
        #expect(row.variance == -3)
        #expect(row.varianceValue == Money(-3000))
        viewModel.setCounted("12.5", for: "A")
        let surplus = try #require(Decimal(string: "2500"))
        #expect(viewModel.rows.first?.varianceValue == Money(surplus))
    }

    @Test("The total sums the value of every valid row and skips an unreadable one")
    func totalSumsValidRows() {
        viewModel.didRead(code: "A", symbology: nil)
        viewModel.didRead(code: "B", symbology: nil)
        viewModel.setCounted("8", for: "A") // −2 × 1000
        viewModel.setCounted("7", for: "B") // +2 × 2500
        #expect(viewModel.totalVarianceValue == Money(3000))
        viewModel.setCounted("abc", for: "B")
        #expect(viewModel.totalVarianceValue == Money(-2000))
        #expect(viewModel.hasInvalidRows)
        #expect(!viewModel.canApply)
    }

    @Test("An unreadable count blocks the apply and writes nothing")
    func invalidCountBlocksApply() throws {
        viewModel.didRead(code: "A", symbology: nil)
        viewModel.setCounted("x", for: "A")
        #expect(!viewModel.apply())
        #expect(viewModel.error == .invalidCount(sku: "A"))
        #expect(try movements().isEmpty)
        #expect(viewModel.rows.count == 1)
    }

    @Test("Applying writes one stocktake movement per changed row and leaves the rest untouched")
    func applyWritesOnlyChangedRowsAndLeavesUnscannedUntouched() throws {
        viewModel.didRead(code: barcodeA, symbology: .ean13)
        viewModel.didRead(code: "B", symbology: nil)
        viewModel.setCounted("7", for: "A")
        viewModel.setCounted("5", for: "B") // matches the system figure

        #expect(viewModel.apply())
        #expect(viewModel.appliedCount == 1)
        #expect(viewModel.rows.isEmpty)
        #expect(viewModel.error == nil)

        let recorded = try movements()
        #expect(recorded.count == 1)
        #expect(recorded.first?.productSKU == "A")
        #expect(recorded.first?.delta == -3)
        #expect(recorded.first?.reasonRaw == "stocktake")
        #expect(recorded.first?.occurredAt == fixedNow)
        #expect(recorded.first?.note == nil)
        #expect(try dependencies.products.product(sku: "A")?.stockOnHand == 7)
        #expect(try dependencies.products.product(sku: "B")?.stockOnHand == 5)
        #expect(try dependencies.products.product(sku: "C")?.stockOnHand == 8)
    }

    @Test("A count that matches everywhere finishes with no movement")
    func matchingCountWritesNothing() throws {
        viewModel.didRead(code: "B", symbology: nil)
        viewModel.setCounted("5", for: "B")
        #expect(viewModel.apply())
        #expect(viewModel.appliedCount == 0)
        #expect(try movements().isEmpty)
    }

    @Test("A failed apply keeps the rows so the count is not lost")
    func applyFailureKeepsRows() throws {
        viewModel.didRead(code: "C", symbology: nil)
        let found = try dependencies.products.product(sku: "C")
        let product = try #require(found)
        try dependencies.transactor.perform {
            dependencies.container.mainContext.delete(product)
        }
        #expect(!viewModel.apply())
        #expect(viewModel.error == .applyFailed)
        #expect(viewModel.rows.count == 1)
    }

    @Test("Removing a row resets the debouncer so the item can be scanned straight back")
    func removeResetsDebouncer() {
        viewModel.didRead(code: "A", symbology: nil)
        viewModel.didRead(code: "B", symbology: nil)
        viewModel.remove(sku: "A")
        #expect(viewModel.rows.map(\.sku) == ["B"])
        viewModel.remove(atOffsets: IndexSet(integer: 0))
        #expect(viewModel.rows.isEmpty)
    }
}
