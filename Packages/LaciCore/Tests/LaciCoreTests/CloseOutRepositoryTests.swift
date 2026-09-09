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
            tradingDay: day, openingFloat: 200_000, cashSales: 12400, cashRefunds: 0, payouts: 0,
            expectedDrawer: 212_400, countedDrawer: counted, discrepancy: counted - 212_400, note: nil,
            closedAt: wib(2026, 9, 9, 21), attribution: nil
        )
    }

    func payout(
        day: Date, kind: PayoutKind = .pettyCash, amount: Decimal = 5000, note: String = "plastik",
        occurredAt: Date? = nil
    ) throws -> Payout {
        try Payout(
            tradingDay: day, kind: kind, amount: amount, note: note, occurredAt: occurredAt ?? wib(2026, 9, 9, 14)
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
        try closeOuts.save(closeOut(day: ninth), cashRemoved: 0)
        #expect(try closeOuts.closeOut(on: ninth)?.discrepancy == 0)
        #expect(try closeOuts.closeOut(on: tenth) == nil)
        #expect(try closeOuts.latest()?.tradingDay == ninth)

        try closeOuts.save(closeOut(day: tenth, counted: 210_000), cashRemoved: 0)
        #expect(try closeOuts.latest()?.tradingDay == tenth)
        #expect(try closeOuts.latest()?.discrepancy == -2400)
    }

    @Test("A day cannot be closed twice")
    func cannotCloseTwice() throws {
        let ninth = try wib(2026, 9, 9)
        try closeOuts.save(closeOut(day: ninth), cashRemoved: 0)
        #expect(throws: CoreError.dayAlreadyClosed(tradingDay: ninth)) {
            try closeOuts.save(closeOut(day: ninth, counted: 0), cashRemoved: 0)
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

    // MARK: Schema

    @Test("Cash refunds and attribution are stored on the row as given")
    func storedColumns() throws {
        let ninth = try wib(2026, 9, 9)
        let row = try closeOut(day: ninth)
        row.cashRefunds = 12400
        row.attribution = Attribution.operatorError.rawValue
        try closeOuts.save(row, cashRemoved: 0)
        let fetched = try #require(try closeOuts.closeOut(on: ninth))
        #expect(fetched.cashRefunds == 12400)
        #expect(fetched.attributionKind == .operatorError)
        #expect(Attribution.operatorError.rawValue == "operator")
    }

    @Test("A payout stores its kind as the SPEC raw string and reads it back typed")
    func payoutKind() throws {
        let ninth = try wib(2026, 9, 9)
        try closeOuts.addPayout(payout(day: ninth, kind: .pettyCash))
        let stored = try #require(try closeOuts.payouts(on: ninth).first)
        #expect(stored.kindRaw == "petty_cash")
        #expect(stored.kind == .pettyCash)
        #expect(PayoutKind.setoran.rawValue == "setoran")
        #expect(PayoutKind.supplier.rawValue == "supplier")
    }

    // MARK: Payouts

    @Test("Payouts are listed and summed per day, oldest first")
    func payoutsPerDay() throws {
        let ninth = try wib(2026, 9, 9)
        try closeOuts.addPayout(payout(day: ninth, amount: 5000, occurredAt: wib(2026, 9, 9, 15)))
        try closeOuts.addPayout(payout(day: ninth, kind: .supplier, amount: 70000, occurredAt: wib(2026, 9, 9, 10)))
        try closeOuts.addPayout(payout(day: wib(2026, 9, 10), amount: 1000))

        #expect(try closeOuts.payouts(on: ninth).map(\.amount) == [70000, 5000])
        #expect(try closeOuts.payoutsTotal(on: ninth) == 75000)
        #expect(try closeOuts.payoutsTotal(on: wib(2026, 9, 8)) == 0)
    }

    @Test("A payout can be deleted while the day is open")
    func deletePayout() throws {
        let ninth = try wib(2026, 9, 9)
        try closeOuts.addPayout(payout(day: ninth))
        let stored = try #require(try closeOuts.payouts(on: ninth).first)
        try closeOuts.deletePayout(stored)
        #expect(try closeOuts.payouts(on: ninth).isEmpty)
    }

    @Test("Payouts cannot be added to or removed from a closed day")
    func payoutsFrozenOnClosedDay() throws {
        let ninth = try wib(2026, 9, 9)
        try closeOuts.addPayout(payout(day: ninth))
        try closeOuts.save(closeOut(day: ninth), cashRemoved: 0)
        let stored = try #require(try closeOuts.payouts(on: ninth).first)

        #expect(throws: CoreError.dayAlreadyClosed(tradingDay: ninth)) {
            try closeOuts.addPayout(payout(day: ninth, amount: 999))
        }
        #expect(throws: CoreError.dayAlreadyClosed(tradingDay: ninth)) {
            try closeOuts.deletePayout(stored)
        }
        #expect(try closeOuts.payouts(on: ninth).map(\.amount) == [5000])
    }

    // MARK: Closing setoran

    @Test("Saving with nothing removed records no payout")
    func saveWithoutSetoran() throws {
        let ninth = try wib(2026, 9, 9)
        try closeOuts.save(closeOut(day: ninth), cashRemoved: 0)
        #expect(try closeOuts.payouts(on: ninth).isEmpty)
    }

    @Test("Saving with cash removed records exactly one setoran payout dated at close")
    func saveWithSetoran() throws {
        let ninth = try wib(2026, 9, 9)
        let row = try closeOut(day: ninth)
        try closeOuts.save(row, cashRemoved: 150_000)
        let payouts = try closeOuts.payouts(on: ninth)
        #expect(payouts.count == 1)
        #expect(payouts.first?.kind == .setoran)
        #expect(payouts.first?.amount == 150_000)
        #expect(payouts.first?.occurredAt == row.closedAt)
    }

    @Test("A rejected second close leaves the first day's payouts untouched")
    func secondCloseIsAtomic() throws {
        let ninth = try wib(2026, 9, 9)
        try closeOuts.save(closeOut(day: ninth), cashRemoved: 100_000)
        #expect(throws: CoreError.dayAlreadyClosed(tradingDay: ninth)) {
            try closeOuts.save(closeOut(day: ninth, counted: 0), cashRemoved: 50000)
        }
        #expect(try closeOuts.payouts(on: ninth).map(\.amount) == [100_000])
        #expect(try store.container.mainContext.fetchCount(FetchDescriptor<Payout>()) == 1)
    }

    // MARK: Opening float

    @Test("There is no opening float to carry forward before the first close-out")
    func noOpeningFloatYet() throws {
        #expect(try closeOuts.nextOpeningFloat() == nil)
    }

    @Test("The next opening float is the latest counted drawer when nothing was removed")
    func openingFloatIsCounted() throws {
        try closeOuts.save(closeOut(day: wib(2026, 9, 9), counted: 210_000), cashRemoved: 0)
        #expect(try closeOuts.nextOpeningFloat() == 210_000)
    }

    @Test("The next opening float is counted minus the setoran, even with a same-instant mid-day payout")
    func openingFloatMinusSetoran() throws {
        let ninth = try wib(2026, 9, 9)
        // A mid-day payout recorded at the very instant the day is closed must still count as
        // pre-count: it is in `CloseOut.payouts`, so it is not part of the removal.
        try closeOuts.addPayout(payout(day: ninth, amount: 20000, occurredAt: wib(2026, 9, 9, 21)))
        let row = try closeOut(day: ninth, counted: 250_000)
        row.payouts = 20000
        try closeOuts.save(row, cashRemoved: 200_000)
        #expect(try closeOuts.nextOpeningFloat() == 50000)
    }

    // MARK: Attribution

    @Test("Attribution can be set after the fact and cleared again")
    func attribution() throws {
        let ninth = try wib(2026, 9, 9)
        try closeOuts.save(closeOut(day: ninth), cashRemoved: 0)
        try closeOuts.setAttribution(on: ninth, .bug)
        #expect(try closeOuts.closeOut(on: ninth)?.attributionKind == .bug)
        try closeOuts.setAttribution(on: ninth, nil)
        #expect(try closeOuts.closeOut(on: ninth)?.attribution == nil)
    }

    @Test("Attributing a day that was never closed is an error")
    func attributionNeedsCloseOut() throws {
        let ninth = try wib(2026, 9, 9)
        #expect(throws: CoreError.closeOutNotFound(tradingDay: ninth)) {
            try closeOuts.setAttribution(on: ninth, .bug)
        }
    }
}
