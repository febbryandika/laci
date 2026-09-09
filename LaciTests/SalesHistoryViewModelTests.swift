import Foundation
@testable import Laci
import LaciCore
import LaciMoney
import Testing

private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor
@Suite("Sales history view model")
struct SalesHistoryViewModelTests {
    let dependencies: Dependencies
    let sell: SellViewModel
    let product: Product

    init() throws {
        dependencies = try Dependencies.inMemory()
        sell = SellViewModel(dependencies: dependencies, now: { fixedNow })
        product = Product(
            sku: "A", name: "Item A", unit: "pcs", cost: 0, price: 12350, tracksStock: true, stockOnHand: 100,
            updatedAt: fixedNow
        )
        try dependencies.products.create(product)
        sell.loadCatalogue()
    }

    /// Sales are rung up the way the app does it, through the sell screen's view model.
    @discardableResult
    func ringUp() throws -> Sale {
        sell.add(product)
        sell.checkoutCash(tendered: Money(100_000))
        return try #require(sell.lastSale)
    }

    func history(pageSize: Int = 50) -> SalesHistoryViewModel {
        SalesHistoryViewModel(dependencies: dependencies, pageSize: pageSize)
    }

    @Test("The list is newest first")
    func newestFirst() throws {
        for _ in 0 ..< 3 {
            try ringUp()
        }
        let viewModel = history()
        viewModel.reload()
        #expect(viewModel.sales.map(\.number) == [3, 2, 1])
        #expect(viewModel.isExhausted)
        #expect(!viewModel.loadFailed)
    }

    @Test("An empty store is an exhausted, empty list")
    func emptyStore() {
        let viewModel = history()
        viewModel.reload()
        #expect(viewModel.sales.isEmpty)
        #expect(viewModel.isExhausted)
    }

    @Test("Pages append by number until the store runs out, then loading more is a no-op")
    func pagesUntilExhausted() throws {
        for _ in 0 ..< 5 {
            try ringUp()
        }
        let viewModel = history(pageSize: 2)
        viewModel.reload()
        #expect(viewModel.sales.map(\.number) == [5, 4])
        #expect(!viewModel.isExhausted)

        viewModel.loadMore()
        #expect(viewModel.sales.map(\.number) == [5, 4, 3, 2])
        #expect(!viewModel.isExhausted)

        viewModel.loadMore()
        #expect(viewModel.sales.map(\.number) == [5, 4, 3, 2, 1])
        #expect(viewModel.isExhausted)

        viewModel.loadMore()
        #expect(viewModel.sales.map(\.number) == [5, 4, 3, 2, 1])
    }

    @Test("A numeric query shows exactly that sale, or nothing")
    func numericQuery() throws {
        for _ in 0 ..< 3 {
            try ringUp()
        }
        let viewModel = history(pageSize: 2)
        viewModel.query = " 2 "
        viewModel.reload()
        #expect(viewModel.sales.map(\.number) == [2])
        #expect(viewModel.isExhausted)
        viewModel.loadMore()
        #expect(viewModel.sales.map(\.number) == [2])

        viewModel.query = "9"
        viewModel.reload()
        #expect(viewModel.sales.isEmpty)
    }

    @Test("A query that is not a number lists everything")
    func nonNumericQuery() throws {
        for _ in 0 ..< 2 {
            try ringUp()
        }
        let viewModel = history()
        viewModel.query = "abc"
        viewModel.reload()
        #expect(viewModel.sales.map(\.number) == [2, 1])
    }
}
