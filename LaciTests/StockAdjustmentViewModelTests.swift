import Foundation
@testable import Laci
import LaciCore
import SwiftData
import Testing

private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
private let barcodeA = "5901234123457"

@MainActor
@Suite("Manual stock adjustment")
struct StockAdjustmentViewModelTests {
    let dependencies: Dependencies
    let viewModel: StockAdjustmentViewModel

    init() throws {
        dependencies = try Dependencies.inMemory()
        viewModel = StockAdjustmentViewModel(dependencies: dependencies, now: { fixedNow })
        try dependencies.products.create(Product(
            sku: "A", name: "Item A", unit: "pcs", cost: 1000, price: 2000, tracksStock: true, stockOnHand: 10,
            updatedAt: fixedNow
        ))
        try dependencies.products.create(Product(
            sku: "U", name: "Pulsa", unit: "pcs", cost: 0, price: 12000, tracksStock: false, updatedAt: fixedNow
        ))
        try dependencies.products.addBarcode(barcodeA, symbology: .ean13, to: "A")
    }

    func movements() throws -> [StockMovement] {
        try dependencies.container.mainContext.fetch(FetchDescriptor<StockMovement>())
    }

    @Test("Stock in adds the quantity with reason stock_in and the note")
    func stockInIsPositive() throws {
        viewModel.skuText = "A"
        viewModel.lookup()
        #expect(viewModel.product?.sku == "A")
        viewModel.kind = .stockIn
        viewModel.quantityText = "12"
        viewModel.note = " Kiriman pagi "
        #expect(viewModel.save())

        let recorded = try movements()
        #expect(recorded.count == 1)
        #expect(recorded.first?.delta == 12)
        #expect(recorded.first?.reasonRaw == "stock_in")
        #expect(recorded.first?.note == "Kiriman pagi")
        #expect(recorded.first?.occurredAt == fixedNow)
        #expect(try dependencies.products.product(sku: "A")?.stockOnHand == 22)
        #expect(viewModel.saved == .init(sku: "A", delta: 12, stockOnHand: 22))
        #expect(viewModel.quantityText.isEmpty)
        #expect(viewModel.note.isEmpty)
    }

    @Test("Waste is typed positive and written negative")
    func wasteIsNegative() throws {
        viewModel.skuText = barcodeA
        viewModel.lookup()
        #expect(viewModel.product?.sku == "A")
        viewModel.kind = .waste
        viewModel.quantityText = "2.5"
        #expect(viewModel.save())
        #expect(try movements().first?.delta == Decimal(string: "-2.5"))
        #expect(try movements().first?.reasonRaw == "waste")
        #expect(try dependencies.products.product(sku: "A")?.stockOnHand == Decimal(string: "7.5"))
    }

    @Test("A blank note is stored as nil")
    func blankNoteStoredAsNil() throws {
        viewModel.skuText = "A"
        viewModel.lookup()
        viewModel.quantityText = "1"
        viewModel.note = "   "
        #expect(viewModel.save())
        #expect(try movements().first?.note == nil)
    }

    @Test("Zero, negative and unreadable quantities are refused", arguments: ["0", "-3", "abc", ""])
    func invalidQuantityRefused(text: String) throws {
        viewModel.skuText = "A"
        viewModel.lookup()
        viewModel.quantityText = text
        #expect(!viewModel.save())
        #expect(viewModel.error == .quantityInvalid)
        #expect(try movements().isEmpty)
    }

    @Test("A product that does not track stock is refused at lookup")
    func untrackedProductRefused() {
        viewModel.skuText = "U"
        viewModel.lookup()
        #expect(viewModel.product == nil)
        #expect(viewModel.error == .untracked)
        viewModel.quantityText = "1"
        #expect(!viewModel.save())
    }

    @Test("An unknown SKU is refused")
    func unknownSKURefused() {
        viewModel.skuText = "ZZ"
        viewModel.lookup()
        #expect(viewModel.product == nil)
        #expect(viewModel.error == .productNotFound)
    }
}
