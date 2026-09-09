import Foundation
import LaciCore
import LaciMoney
import SwiftData
import Testing

@MainActor
@Suite("Close-out repository")
struct CloseOutRepositoryTests {
    let store: TestStore
    let products: SwiftDataProductRepository
    let sales: SwiftDataSaleRepository
    let closeOuts: SwiftDataCloseOutRepository

    init() throws {
        store = try TestStore()
        let transactor = Transactor(container: store.container)
        products = SwiftDataProductRepository(transactor: transactor)
        sales = SwiftDataSaleRepository(transactor: transactor)
        closeOuts = SwiftDataCloseOutRepository(transactor: transactor)
        try products.create(makeProduct("A", tracksStock: false, price: 12350))
    }

    func closeOut(day: Date, counted: Decimal = 212_400) throws -> CloseOut {
        try CloseOut(
            tradingDay: day, openingFloat: 200_000, cashSales: 12400, payouts: 0, expectedDrawer: 212_400,
            countedDrawer: counted, discrepancy: counted - 212_400, note: nil,
            closedAt: wib(2026, 9, 9, 21), attribution: nil
        )
    }

    func sell(_ payment: SaleDraft.Payment, occurredAt: Date) throws -> Sale {
        let cart = CartLine(
            sku: "A", name: "Item A", quantity: 1, unitPrice: Money(12350), discount: .none, taxable: true
        )
        let lines = [SaleDraft.Line(cart: cart, listPrice: Money(12350))]
        let totals = Pricing.totals(lines: [cart], saleDiscount: .none, tax: .nonPKP)
        let draft = SaleDraft(lines: lines, totals: totals, payment: payment, occurredAt: occurredAt)
        return try sales.commit(draft, tradingDay: TradingDay(cutoverHour: 2), timeZone: jakarta)
    }

    func cash() throws -> SaleDraft.Payment {
        try .cash(#require(Tender.settle(total: Money(12350), tendered: Money(20000))))
    }

    @Test("A saved close-out is found by day and is the latest")
    func saveAndFetch() throws {
        let ninth = try wib(2026, 9, 9)
        let tenth = try wib(2026, 9, 10)
        try closeOuts.save(closeOut(day: ninth))
        #expect(try closeOuts.closeOut(on: ninth)?.discrepancy == 0)
        #expect(try closeOuts.closeOut(on: tenth) == nil)
        #expect(try closeOuts.latest()?.tradingDay == ninth)

        try closeOuts.save(closeOut(day: tenth, counted: 210_000))
        #expect(try closeOuts.latest()?.tradingDay == tenth)
        #expect(try closeOuts.latest()?.discrepancy == -2400)
    }

    @Test("A day cannot be closed twice")
    func cannotCloseTwice() throws {
        let ninth = try wib(2026, 9, 9)
        try closeOuts.save(closeOut(day: ninth))
        #expect(throws: CoreError.dayAlreadyClosed(tradingDay: ninth)) {
            try closeOuts.save(closeOut(day: ninth, counted: 0))
        }
        #expect(try store.container.mainContext.fetchCount(FetchDescriptor<CloseOut>()) == 1)
        #expect(try closeOuts.closeOut(on: ninth)?.countedDrawer == 212_400)
    }

    @Test("Cash sales for a day sum the rounded totals of non-voided cash sales only")
    func cashSales() throws {
        let noon = try wib(2026, 9, 9, 12)
        _ = try sell(cash(), occurredAt: noon)
        _ = try sell(.qris(reference: "QR-1"), occurredAt: noon)
        let voided = try sell(cash(), occurredAt: noon)
        try sales.void(saleID: voided.id, reason: "salah input", occurredAt: wib(2026, 9, 9, 13))
        _ = try sell(cash(), occurredAt: wib(2026, 9, 10, 12)) // tomorrow

        #expect(try closeOuts.cashSales(on: wib(2026, 9, 9)) == 12400)
        #expect(try closeOuts.cashSales(on: wib(2026, 9, 8)) == 0)
    }

    @Test("Cash refunds are a separate positive figure and never net into cash sales")
    func cashRefunds() throws {
        let noon = try wib(2026, 9, 9, 12)
        let ninth = try wib(2026, 9, 9)
        let cashSale = try sell(cash(), occurredAt: noon)
        let qrisSale = try sell(.qris(reference: "QR-1"), occurredAt: noon)
        _ = try sell(cash(), occurredAt: noon)
        for sale in [cashSale, qrisSale] {
            _ = try sales.refund(
                saleID: sale.id, occurredAt: wib(2026, 9, 9, 14), tradingDay: TradingDay(cutoverHour: 2),
                timeZone: jakarta
            )
        }

        #expect(try closeOuts.cashSales(on: ninth) == 24800)
        #expect(try closeOuts.cashRefunds(on: ninth) == 12400)
        #expect(try closeOuts.cashRefunds(on: wib(2026, 9, 8)) == 0)
    }
}
