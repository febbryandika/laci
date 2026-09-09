import Foundation
import LaciCore
import LaciMoney
import SwiftData
import Testing

@MainActor
@Suite("Sale repository")
struct SaleRepositoryTests {
    let store: TestStore
    let products: SwiftDataProductRepository
    let sales: SwiftDataSaleRepository
    let cutover = TradingDay(cutoverHour: 2)

    init() throws {
        store = try TestStore()
        let transactor = Transactor(container: store.container)
        products = SwiftDataProductRepository(transactor: transactor)
        sales = SwiftDataSaleRepository(transactor: transactor)
        try products.create(makeProduct("A", stockOnHand: 10, price: 5000))
        try products.create(makeProduct("U", tracksStock: false, price: 3000))
    }

    func line(
        _ sku: String, qty: Decimal = 1, price: Decimal = 5000, list: Decimal? = nil, discount: Discount = .none
    ) -> SaleDraft.Line {
        let cart = CartLine(
            sku: sku, name: "Item \(sku)", quantity: qty, unitPrice: Money(price), discount: discount, taxable: true
        )
        return SaleDraft.Line(cart: cart, listPrice: Money(list ?? price))
    }

    func totals(_ lines: [SaleDraft.Line]) -> SaleTotals {
        Pricing.totals(lines: lines.map(\.cart), saleDiscount: .none, tax: .nonPKP)
    }

    func cashDraft(
        _ lines: [SaleDraft.Line], tendered: Decimal = 100_000, occurredAt: Date? = nil
    ) throws -> SaleDraft {
        let totals = totals(lines)
        let settlement = try #require(Tender.settle(total: totals.grandTotal, tendered: Money(tendered)))
        return try SaleDraft(lines: lines, totals: totals, payment: .cash(settlement),
                             occurredAt: occurredAt ?? wib(2026, 9, 10, 12))
    }

    func commit(_ draft: SaleDraft) throws -> Sale {
        try sales.commit(draft, tradingDay: cutover, timeZone: jakarta)
    }

    @Test("Only stock-tracked lines decrement stock, each with a sale movement")
    func stockDecrements() throws {
        let sale = try commit(cashDraft([line("A", qty: 2), line("U", price: 3000)]))

        #expect(try products.product(sku: "A")?.stockOnHand == 8)
        #expect(try products.product(sku: "U")?.stockOnHand == 0)
        let movements = try store.container.mainContext.fetch(FetchDescriptor<StockMovement>())
        #expect(movements.count == 1)
        #expect(movements.first?.productSKU == "A")
        #expect(movements.first?.delta == -2)
        #expect(movements.first?.reasonRaw == "sale")
        #expect(movements.first?.saleID == sale.id)
    }

    @Test("Sale numbers are monotonic per install")
    func numbers() throws {
        var numbers: [Int] = []
        for _ in 0 ..< 3 {
            try numbers.append(commit(cashDraft([line("A")])).number)
        }
        #expect(numbers == [1, 2, 3])
        #expect(try sales.nextNumber() == 4)
    }

    @Test("The trading day is bucketed at commit and never recomputed")
    func tradingDayStored() throws {
        let sale = try commit(cashDraft([line("A")], occurredAt: wib(2026, 9, 10, 1, 30)))
        let expected = try wib(2026, 9, 9)
        #expect(sale.tradingDay == expected)

        // A later commit under a different cutover leaves the stored value alone.
        let laterDraft = try cashDraft([line("A")], occurredAt: wib(2026, 9, 10, 1, 45))
        _ = try sales.commit(laterDraft, tradingDay: TradingDay(cutoverHour: 6), timeZone: jakarta)
        #expect(try sales.sale(id: sale.id)?.tradingDay == expected)
        #expect(try sales.sales(on: expected, limit: 10).map(\.number) == [1, 2])
    }

    @Test("Cash stores the rounded total, the signed delta, tender and change")
    func cashFields() throws {
        let sale = try commit(cashDraft([line("A", price: 12350)], tendered: 20000))
        #expect(sale.total == 12400)
        #expect(sale.roundingDelta == 50)
        #expect(sale.subtotal == 12350)
        #expect(sale.amountTendered == 20000)
        #expect(sale.changeGiven == 7600)
        #expect(sale.reference == nil)
        #expect(sale.paymentMethod == .cash)
    }

    @Test("Non-cash charges the exact total with a reference and no rounding")
    func qrisFields() throws {
        let lines = [line("A", price: 12350)]
        let draft = try SaleDraft(lines: lines, totals: totals(lines), payment: .qris(reference: "QR-1"),
                                  occurredAt: wib(2026, 9, 10, 12))
        let sale = try commit(draft)
        #expect(sale.total == 12350)
        #expect(sale.roundingDelta == 0)
        #expect(sale.reference == "QR-1")
        #expect(sale.amountTendered == nil)
        #expect(sale.changeGiven == nil)
        #expect(sale.paymentMethod == .qris)
    }

    @Test("A line denormalises name, keeps the list price and resolves percent to an amount")
    func lineFields() throws {
        let draftLine = line("A", price: 4500, list: 5000, discount: .percent(10))
        let sale = try commit(cashDraft([draftLine]))
        let stored = try #require(sale.lines.first)
        #expect(stored.productSKU == "A")
        #expect(stored.name == "Item A")
        #expect(stored.unitPrice == 4500)
        #expect(stored.listPrice == 5000)
        #expect(stored.discountAmount == Pricing.total(for: draftLine.cart).discount.amount)
        #expect(stored.discountAmount == 450)
        #expect(stored.lineTotal == 4050)
        #expect(stored.sale?.id == sale.id)
    }

    @Test("A missing product rolls back the sale, its lines and any stock change")
    func missingProductRollsBack() throws {
        let draft = try cashDraft([line("A"), line("ZZ")])
        #expect(throws: CoreError.productNotFound(sku: "ZZ")) { try commit(draft) }

        let fresh = ModelContext(store.container)
        #expect(try fresh.fetchCount(FetchDescriptor<Sale>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<SaleLine>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<StockMovement>()) == 0)
        #expect(try products.product(sku: "A")?.stockOnHand == 10)
        #expect(try sales.nextNumber() == 1)
    }

    @Test("An empty draft is refused")
    func emptyDraft() throws {
        let draft = try SaleDraft(lines: [], totals: totals([]), payment: .qris(reference: "x"),
                                  occurredAt: wib(2026, 9, 10, 12))
        #expect(throws: CoreError.emptySale) { try commit(draft) }
    }

    @Test("A cash settlement computed for a different total is refused")
    func settlementMismatch() throws {
        let lines = [line("A")]
        let wrong = try #require(Tender.settle(total: Money(99999), tendered: Money(100_000)))
        let draft = try SaleDraft(lines: lines, totals: totals(lines), payment: .cash(wrong),
                                  occurredAt: wib(2026, 9, 10, 12))
        #expect(throws: CoreError.settlementMismatch) { try commit(draft) }
    }
}
