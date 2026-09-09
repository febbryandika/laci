import Foundation
@testable import Laci
import LaciCore
import LaciMoney
import Testing

/// A fixed clock: a test that fails at midnight is a broken test.
private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor
@Suite("Sell view model")
struct SellViewModelTests {
    let dependencies: Dependencies
    let viewModel: SellViewModel

    init() throws {
        dependencies = try Dependencies.inMemory()
        viewModel = SellViewModel(dependencies: dependencies, now: { fixedNow })
    }

    @discardableResult
    func seed(
        _ sku: String, name: String? = nil, price: Decimal = 12350, tracksStock: Bool = true, stock: Decimal = 10
    ) throws -> Product {
        let product = Product(
            sku: sku, name: name ?? "Item \(sku)", unit: "pcs", cost: 0, price: price, tracksStock: tracksStock,
            stockOnHand: stock, updatedAt: fixedNow
        )
        try dependencies.products.create(product)
        viewModel.loadCatalogue()
        return product
    }

    var tradingDay: Date {
        ShopDefaults.tradingDay.bucket(for: fixedNow, timeZone: ShopDefaults.timeZone)
    }

    // MARK: Cart transitions

    @Test("Adding the same SKU twice increments one line and keeps the list price")
    func sameSKUIncrementsOneLine() throws {
        let product = try seed("A")
        viewModel.add(product)
        viewModel.add(product)
        #expect(viewModel.lines.count == 1)
        #expect(viewModel.lines.first?.cart.quantity == 2)
        #expect(viewModel.lines.first?.listPrice == Money(12350))
    }

    @Test("Removing a line and adding the SKU again starts a fresh line at quantity one")
    func removeThenReAdd() throws {
        let product = try seed("A")
        viewModel.add(product)
        viewModel.add(product)
        viewModel.remove(sku: "A")
        #expect(viewModel.lines.isEmpty)
        viewModel.add(product)
        #expect(viewModel.lines.map(\.cart.quantity) == [1])
    }

    @Test("Decrementing never drops a line below one")
    func decrementFloor() throws {
        try viewModel.add(seed("A"))
        viewModel.decrement(sku: "A")
        #expect(viewModel.lines.first?.cart.quantity == 1)
        viewModel.setQuantity(sku: "A", 0)
        #expect(viewModel.lines.first?.cart.quantity == 1)
        viewModel.setQuantity(sku: "A", Decimal(string: "0.5") ?? 0)
        #expect(viewModel.lines.first?.cart.quantity == Decimal(string: "0.5"))
    }

    @Test("A price override is charged while the list price is retained on the stored line")
    func priceOverrideKeepsListPrice() throws {
        try viewModel.add(seed("A", price: 5000))
        viewModel.setUnitPrice(sku: "A", Money(4500))
        viewModel.checkoutCash(tendered: Money(100_000))
        let stored = try #require(viewModel.lastSale?.lines.first)
        #expect(stored.unitPrice == 4500)
        #expect(stored.listPrice == 5000)
        #expect(stored.lineTotal == 4500)
    }

    @Test(
        "A line discount is persisted as the amount Pricing resolves",
        arguments: [(Discount.amount(Money(700)), Decimal(700), Decimal(3800)), (.percent(10), 450, 4050)]
    )
    func lineDiscountPersists(discount: Discount, expectedDiscount: Decimal, expectedTotal: Decimal) throws {
        try viewModel.add(seed("A", price: 4500))
        viewModel.setDiscount(sku: "A", discount)
        let line = try #require(viewModel.line(sku: "A"))
        #expect(viewModel.lineTotal(for: line) == Pricing.total(for: line.cart))
        viewModel.checkoutCash(tendered: Money(100_000))
        let stored = try #require(viewModel.lastSale?.lines.first)
        #expect(stored.discountAmount == expectedDiscount)
        #expect(stored.discountAmount == Pricing.total(for: line.cart).discount.amount)
        #expect(stored.lineTotal == expectedTotal)
    }

    @Test("A negative amount discount is ignored on a line and on the sale")
    func negativeDiscountIgnored() throws {
        try viewModel.add(seed("A"))
        viewModel.setDiscount(sku: "A", .amount(Money(-5)))
        viewModel.setSaleDiscount(.amount(Money(-5)))
        #expect(viewModel.line(sku: "A")?.cart.discount == Discount.none)
        #expect(viewModel.saleDiscount == Discount.none)
    }

    @Test("A whole-sale discount flows through SaleTotals into the stored sale")
    func wholeSaleDiscount() throws {
        try viewModel.add(seed("A", price: 4500))
        try viewModel.add(seed("B", price: 3000))
        viewModel.setDiscount(sku: "A", .amount(Money(500)))
        viewModel.setSaleDiscount(.amount(Money(1000)))
        #expect(viewModel.totals.saleDiscount == Money(1000))
        #expect(viewModel.totals.grandTotal == Money(6000))
        viewModel.checkoutCash(tendered: Money(6000))
        let sale = try #require(viewModel.lastSale)
        #expect(sale.subtotal == 7000)
        #expect(sale.discountTotal == 1500)
        #expect(sale.total == 6000)
    }

    // MARK: Tender rejection

    @Test("Cash below the rounded total is refused in the view model and nothing reaches the store")
    func cashShortIsRejected() throws {
        try viewModel.add(seed("A"))
        viewModel.checkoutCash(tendered: Money(12350))
        #expect(viewModel.tenderError == .cashShort(rounded: Money(12400)))
        #expect(viewModel.lastSale == nil)
        #expect(viewModel.lines.count == 1)
        #expect(try dependencies.sales.nextNumber() == 1)
        #expect(try dependencies.stock.movements(for: "A", limit: 10).isEmpty)
        #expect(try dependencies.products.product(sku: "A")?.stockOnHand == 10)
    }

    @Test("An empty cart cannot check out")
    func emptyCartIsRejected() throws {
        viewModel.checkoutCash(tendered: Money(100_000))
        #expect(viewModel.tenderError == .emptyCart)
        viewModel.checkoutNonCash(.qris, reference: "REF")
        #expect(viewModel.tenderError == .emptyCart)
        #expect(try dependencies.sales.nextNumber() == 1)
    }

    @Test("Non-cash without a reference is refused")
    func blankReferenceIsRejected() throws {
        try viewModel.add(seed("A"))
        viewModel.checkoutNonCash(.transfer, reference: "  \n")
        #expect(viewModel.tenderError == .missingReference)
        #expect(viewModel.lines.count == 1)
        #expect(try dependencies.sales.nextNumber() == 1)
    }

    // MARK: Persistence

    @Test("Cash at exactly the rounded total stores the delta and zero change")
    func cashExactStoresDelta() throws {
        try viewModel.add(seed("A"))
        viewModel.checkoutCash(tendered: Money(12400))
        let sale = try #require(viewModel.lastSale)
        #expect(sale.total == 12400)
        #expect(sale.roundingDelta == 50)
        #expect(sale.amountTendered == 12400)
        #expect(sale.changeGiven == 0)
        #expect(sale.paymentMethod == .cash)
        #expect(sale.tradingDay == tradingDay)
    }

    @Test("Cash above the rounded total stores the change")
    func cashOverStoresChange() throws {
        try viewModel.add(seed("A"))
        viewModel.checkoutCash(tendered: Money(20000))
        #expect(viewModel.lastSale?.changeGiven == 7600)
        #expect(viewModel.lastSale?.roundingDelta == 50)
    }

    @Test("Sale numbers are monotonic across checkouts")
    func numbersAreMonotonic() throws {
        let product = try seed("A")
        var numbers: [Int] = []
        for _ in 0 ..< 2 {
            viewModel.add(product)
            viewModel.checkoutCash(tendered: Money(100_000))
            try numbers.append(#require(viewModel.lastSale?.number))
        }
        #expect(numbers == [1, 2])
        #expect(try dependencies.sales.nextNumber() == 3)
        #expect(try dependencies.sales.sales(on: tradingDay, limit: 10).count == 2)
    }

    @Test("Non-cash charges the exact total with a reference and no rounding", arguments: NonCashMethod.allCases)
    func nonCashIsExact(method: NonCashMethod) throws {
        try viewModel.add(seed("A"))
        viewModel.checkoutNonCash(method, reference: " REF-1 ")
        let sale = try #require(viewModel.lastSale)
        #expect(sale.total == 12350)
        #expect(sale.roundingDelta == 0)
        #expect(sale.reference == "REF-1")
        #expect(sale.amountTendered == nil)
        #expect(sale.changeGiven == nil)
        #expect(sale.paymentMethodRaw == method.rawValue)
    }

    @Test("Only stock-tracked products produce a stock movement")
    func stockMovements() throws {
        let tracked = try seed("A")
        viewModel.add(tracked)
        viewModel.add(tracked)
        try viewModel.add(seed("U", price: 3000, tracksStock: false, stock: 0))
        viewModel.checkoutCash(tendered: Money(100_000))
        let sale = try #require(viewModel.lastSale)

        #expect(try dependencies.stock.movements(for: "U", limit: 10).isEmpty)
        #expect(try dependencies.products.product(sku: "U")?.stockOnHand == 0)
        let movements = try dependencies.stock.movements(for: "A", limit: 10)
        #expect(movements.count == 1)
        #expect(movements.first?.delta == -2)
        #expect(movements.first?.reason == .sale)
        #expect(movements.first?.saleID == sale.id)
        #expect(try dependencies.products.product(sku: "A")?.stockOnHand == 8)
    }

    @Test("A committed sale clears the cart, the sale discount, the query and any error")
    func cartClearsAfterCommit() throws {
        try viewModel.add(seed("A"))
        viewModel.setSaleDiscount(.percent(5))
        viewModel.query = "ite"
        viewModel.checkoutCash(tendered: Money(1000))
        #expect(viewModel.tenderError != nil)
        viewModel.checkoutCash(tendered: Money(100_000))
        #expect(viewModel.lines.isEmpty)
        #expect(viewModel.saleDiscount == Discount.none)
        #expect(viewModel.query.isEmpty)
        #expect(viewModel.tenderError == nil)
        #expect(viewModel.totals.grandTotal == .zero)
        #expect(viewModel.lastSale?.number == 1)
    }

    // MARK: Search

    @Test("Search matches name or SKU case-insensitively and hides archived products")
    func searchFilters() throws {
        try seed("IDM-01", name: "Indomie Goreng")
        try seed("SB-02", name: "Susu Bendera")
        try seed("OLD-03", name: "Arsip")
        try dependencies.products.archive(sku: "OLD-03", updatedAt: fixedNow)
        viewModel.loadCatalogue()

        #expect(viewModel.results.map(\.sku) == ["IDM-01", "SB-02"])
        viewModel.query = "indo"
        #expect(viewModel.results.map(\.sku) == ["IDM-01"])
        viewModel.query = "sb-02"
        #expect(viewModel.results.map(\.sku) == ["SB-02"])
        viewModel.query = "xyz"
        #expect(viewModel.results.isEmpty)
    }

    @Test("Return adds the first result and clears the query; no match leaves the cart alone")
    func returnAddsFirstResult() throws {
        try seed("IDM-01", name: "Indomie Goreng")
        try seed("SB-02", name: "Susu Bendera")
        viewModel.query = "susu"
        viewModel.addFirstResult()
        #expect(viewModel.lines.map(\.cart.sku) == ["SB-02"])
        #expect(viewModel.query.isEmpty)
        viewModel.query = "zzz"
        viewModel.addFirstResult()
        #expect(viewModel.lines.count == 1)
        #expect(viewModel.query == "zzz")
    }

    @Test("The cash total and quick-tender suggestions come from Tender")
    func cashFiguresComeFromTender() throws {
        try viewModel.add(seed("A"))
        #expect(viewModel.cashTotal == Money(12400))
        #expect(viewModel.cashSuggestions.map(\.amount) == [12400, 13000, 14000, 15000, 20000])
        #expect(viewModel.settle(tendered: Money(12350)) == nil)
        #expect(viewModel.settle(tendered: Money(13000))?.change == Money(600))
    }
}
