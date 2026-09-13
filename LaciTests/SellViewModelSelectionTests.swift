import Foundation
@testable import Laci
import LaciCore
import LaciMoney
import Testing

private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor
@Suite("Sell view model selection")
struct SellViewModelSelectionTests {
    let dependencies: Dependencies
    let viewModel: SellViewModel

    init() throws {
        dependencies = try Dependencies.inMemory()
        viewModel = SellViewModel(dependencies: dependencies, now: { fixedNow })
    }

    /// Seeds and adds the SKUs in order, so the cart is `skus` top to bottom.
    func cart(_ skus: String...) throws {
        for sku in skus {
            let product = Product(
                sku: sku, name: "Item \(sku)", unit: "pcs", cost: 0, price: 1000, tracksStock: false,
                stockOnHand: 0, updatedAt: fixedNow
            )
            try dependencies.products.create(product)
            viewModel.add(product)
        }
    }

    @Test("Adding selects the line just added, whether new or incremented")
    func addSelects() throws {
        try cart("A", "B")
        #expect(viewModel.selectedSKU == "B")
        let stored = try dependencies.products.product(sku: "A")
        let product = try #require(stored)
        viewModel.add(product)
        #expect(viewModel.selectedSKU == "A")
        #expect(viewModel.selectedLine?.cart.quantity == 2)
    }

    @Test("Next and previous walk the cart and stop at the ends")
    func walk() throws {
        try cart("A", "B", "C")
        viewModel.select(sku: nil)
        viewModel.selectNext()
        #expect(viewModel.selectedSKU == "A")
        viewModel.selectNext()
        viewModel.selectNext()
        viewModel.selectNext()
        #expect(viewModel.selectedSKU == "C")
        viewModel.selectPrevious()
        #expect(viewModel.selectedSKU == "B")
        viewModel.selectPrevious()
        viewModel.selectPrevious()
        #expect(viewModel.selectedSKU == "A")
    }

    @Test("Previous from nothing starts at the last line")
    func previousFromNothing() throws {
        try cart("A", "B")
        viewModel.select(sku: nil)
        viewModel.selectPrevious()
        #expect(viewModel.selectedSKU == "B")
    }

    @Test("An empty cart selects nothing")
    func emptyCart() {
        viewModel.selectNext()
        viewModel.selectPrevious()
        viewModel.removeSelected()
        viewModel.incrementSelected()
        #expect(viewModel.selectedSKU == nil)
        #expect(viewModel.lines.isEmpty)
    }

    @Test("A SKU not in the cart cannot be selected")
    func unknownSKU() throws {
        try cart("A")
        viewModel.select(sku: "nope")
        #expect(viewModel.selectedSKU == "A")
    }

    @Test("Removing the middle line selects the one that took its place")
    func removeMiddle() throws {
        try cart("A", "B", "C")
        viewModel.select(sku: "B")
        viewModel.removeSelected()
        #expect(viewModel.lines.map(\.cart.sku) == ["A", "C"])
        #expect(viewModel.selectedSKU == "C")
    }

    @Test("Removing the last line selects the previous one; removing the only line clears")
    func removeLast() throws {
        try cart("A", "B")
        viewModel.removeSelected()
        #expect(viewModel.selectedSKU == "A")
        viewModel.removeSelected()
        #expect(viewModel.selectedSKU == nil)
        #expect(viewModel.lines.isEmpty)
    }

    @Test("Removing an unselected line keeps the selection")
    func removeOther() throws {
        try cart("A", "B")
        viewModel.select(sku: "A")
        viewModel.remove(sku: "B")
        #expect(viewModel.selectedSKU == "A")
    }

    @Test("Plus and minus change the selected quantity and floor at one")
    func quantity() throws {
        try cart("A")
        viewModel.incrementSelected()
        viewModel.incrementSelected()
        #expect(viewModel.selectedLine?.cart.quantity == 3)
        viewModel.decrementSelected()
        viewModel.decrementSelected()
        viewModel.decrementSelected()
        #expect(viewModel.selectedLine?.cart.quantity == 1)
    }

    @Test("A checkout clears the selection with the cart")
    func checkoutClears() throws {
        try cart("A")
        viewModel.checkoutCash(tendered: Money(1000))
        #expect(viewModel.tenderError == nil)
        #expect(viewModel.selectedSKU == nil)
    }
}
