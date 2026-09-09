import Foundation
import LaciCore
import LaciMoney
import SwiftData
import Testing

/// Void and refund (SPEC §3.1.6): a void marks and reverses, a refund is its own linked sale, and
/// neither touches the committed rows beyond the void fields.
@MainActor
@Suite("Sale void and refund")
struct SaleCorrectionTests {
    let store: TestStore
    let products: SwiftDataProductRepository
    let sales: SwiftDataSaleRepository
    let cutover = TradingDay(cutoverHour: 2)

    init() throws {
        store = try TestStore()
        let transactor = Transactor(container: store.container)
        products = SwiftDataProductRepository(transactor: transactor)
        sales = SwiftDataSaleRepository(transactor: transactor)
        try products.create(makeProduct("A", stockOnHand: 10, price: 6175))
        try products.create(makeProduct("U", tracksStock: false, price: 3000))
    }

    /// Two of A at a 10% discount (gross 12.350, net 11.115) plus one untracked U: subtotal 14.115,
    /// which rounds down to 14.100 for cash.
    func sell(occurredAt: Date? = nil) throws -> Sale {
        let lines = [line("A", qty: 2, price: 6175, discount: .percent(10)), line("U", price: 3000)]
        return try sales.commit(cashDraft(lines, occurredAt: occurredAt), tradingDay: cutover, timeZone: jakarta)
    }

    func void(_ sale: Sale, reason: String = "salah input") throws {
        try sales.void(saleID: sale.id, reason: reason, occurredAt: wib(2026, 9, 10, 13))
    }

    func refund(_ sale: Sale) throws -> Sale {
        try sales.refund(saleID: sale.id, occurredAt: wib(2026, 9, 11, 10), tradingDay: cutover, timeZone: jakarta)
    }

    func movements(reason: String) throws -> [StockMovement] {
        try store.container.mainContext.fetch(FetchDescriptor<StockMovement>(
            predicate: #Predicate { $0.reasonRaw == reason }, sortBy: [SortDescriptor(\.occurredAt)]
        ))
    }

    func stock(_ sku: String) throws -> Decimal? {
        try products.product(sku: sku)?.stockOnHand
    }

    // MARK: Void

    @Test("A void marks the sale, restores stock once with one void movement per tracked line, and deletes nothing")
    func voidRestoresStock() throws {
        let sale = try sell()
        try void(sale)

        #expect(try sale.voidedAt == wib(2026, 9, 10, 13))
        #expect(sale.voidReason == "salah input")
        #expect(sale.total == 14100)
        #expect(sale.lines.count == 2)
        #expect(try stock("A") == 10)
        let voids = try movements(reason: "void")
        #expect(voids.count == 1)
        #expect(voids.first?.productSKU == "A")
        #expect(voids.first?.delta == 2)
        #expect(voids.first?.saleID == sale.id)

        let fresh = ModelContext(store.container)
        #expect(try fresh.fetchCount(FetchDescriptor<Sale>()) == 1)
        #expect(try fresh.fetchCount(FetchDescriptor<SaleLine>()) == 2)
        #expect(try fresh.fetchCount(FetchDescriptor<StockMovement>()) == 2)
    }

    @Test("A second void is rejected and moves no stock")
    func doubleVoidIsRejected() throws {
        let sale = try sell()
        try void(sale)
        #expect(throws: CoreError.saleAlreadyVoided(id: sale.id)) { try void(sale, reason: "lagi") }
        #expect(sale.voidReason == "salah input")
        #expect(try stock("A") == 10)
        #expect(try movements(reason: "void").count == 1)
    }

    @Test("A blank reason is rejected before anything changes", arguments: ["", "   ", "\n"])
    func blankReasonIsRejected(reason: String) throws {
        let sale = try sell()
        #expect(throws: CoreError.voidReasonRequired) { try void(sale, reason: reason) }
        #expect(sale.voidedAt == nil)
        #expect(try stock("A") == 8)
        #expect(try movements(reason: "void").isEmpty)
    }

    @Test("The reason is stored trimmed")
    func reasonIsTrimmed() throws {
        let sale = try sell()
        try void(sale, reason: "  rusak \n")
        #expect(sale.voidReason == "rusak")
    }

    @Test("Voiding an unknown sale is rejected")
    func unknownSaleIsRejected() throws {
        let id = UUID()
        #expect(throws: CoreError.saleNotFound(id: id)) {
            try sales.void(saleID: id, reason: "x", occurredAt: wib(2026, 9, 10, 13))
        }
    }

    @Test("A sale with a live refund cannot be voided")
    func refundedSaleCannotBeVoided() throws {
        let sale = try sell()
        _ = try refund(sale)
        #expect(throws: CoreError.saleHasLiveRefund(id: sale.id)) { try void(sale) }
        #expect(sale.voidedAt == nil)
        #expect(try stock("A") == 10)
    }

    // MARK: Refund

    @Test("A refund is a new linked sale with every line and total negated and stock restored")
    func refundMirrorsTheSale() throws {
        let sale = try sell()
        let refund = try refund(sale)

        #expect(refund.number == sale.number + 1)
        #expect(refund.refundsSaleID == sale.id)
        #expect(try refund.occurredAt == wib(2026, 9, 11, 10))
        #expect(try refund.tradingDay == wib(2026, 9, 11))
        #expect(refund.subtotal == -14115)
        #expect(refund.discountTotal == -1235)
        #expect(refund.taxTotal == 0)
        #expect(refund.roundingDelta == 15)
        #expect(refund.total == -14100)
        #expect(refund.paymentMethod == .cash)
        #expect(refund.amountTendered == nil)
        #expect(refund.changeGiven == nil)
        #expect(refund.reference == nil)
        #expect(refund.voidedAt == nil)

        let lines = refund.lines.sorted { $0.productSKU < $1.productSKU }
        #expect(lines.map(\.quantity) == [-2, -1])
        #expect(lines.map(\.productSKU) == ["A", "U"])
        #expect(lines.first?.name == "Item A")
        #expect(lines.first?.unitPrice == 6175)
        #expect(lines.first?.listPrice == 6175)
        #expect(lines.first?.discountAmount == -1235)
        #expect(lines.first?.lineTotal == -11115)
        #expect(lines.first?.sale?.id == refund.id)

        #expect(try stock("A") == 10)
        let restocks = try movements(reason: "sale").filter { $0.saleID == refund.id }
        #expect(restocks.count == 1)
        #expect(restocks.first?.productSKU == "A")
        #expect(restocks.first?.delta == 2)
        #expect(try sales.refunds(of: sale.id).map(\.id) == [refund.id])
        #expect(sale.voidedAt == nil)
        #expect(sale.total == 14100)
    }

    @Test("A non-cash refund keeps the exact total, the method and the reference")
    func nonCashRefundCopiesTheChannel() throws {
        let lines = [line("A", price: 6175)]
        let draft = try SaleDraft(lines: lines, totals: totals(lines), payment: .qris(reference: "QR-1"),
                                  occurredAt: wib(2026, 9, 10, 12))
        let sale = try sales.commit(draft, tradingDay: cutover, timeZone: jakarta)
        let refund = try refund(sale)
        #expect(refund.total == -6175)
        #expect(refund.roundingDelta == 0)
        #expect(refund.paymentMethod == .qris)
        #expect(refund.reference == "QR-1")
    }

    @Test("A voided sale cannot be refunded")
    func voidedSaleCannotBeRefunded() throws {
        let sale = try sell()
        try void(sale)
        #expect(throws: CoreError.saleAlreadyVoided(id: sale.id)) { try refund(sale) }
        let fresh = ModelContext(store.container)
        #expect(try fresh.fetchCount(FetchDescriptor<Sale>()) == 1)
        #expect(try sales.nextNumber() == 2)
        #expect(try stock("A") == 10)
    }

    @Test("A sale can be refunded only once")
    func secondRefundIsRejected() throws {
        let sale = try sell()
        _ = try refund(sale)
        #expect(throws: CoreError.saleHasLiveRefund(id: sale.id)) { try refund(sale) }
        #expect(try sales.nextNumber() == 3)
        #expect(try stock("A") == 10)
    }

    @Test("A refund cannot itself be refunded")
    func refundOfRefundIsRejected() throws {
        let refund = try refund(sell())
        #expect(throws: CoreError.saleIsRefund(id: refund.id)) { try self.refund(refund) }
        #expect(try sales.nextNumber() == 3)
    }

    @Test("Voiding a refund takes the stock back and reopens the original for refund")
    func voidingARefundReopensTheSale() throws {
        let sale = try sell()
        let first = try refund(sale)
        try void(first, reason: "retur dibatalkan")

        #expect(try stock("A") == 8)
        #expect(try movements(reason: "void").first?.delta == -2)
        #expect(try sales.refunds(of: sale.id).isEmpty)

        let second = try refund(sale)
        #expect(second.number == 3)
        #expect(try stock("A") == 10)
        #expect(try sales.refunds(of: sale.id).map(\.id) == [second.id])
    }

    // MARK: History queries

    @Test("Recent sales page newest first by number")
    func recentPagesByNumber() throws {
        for _ in 0 ..< 5 {
            _ = try sell()
        }
        #expect(try sales.recent(before: nil, limit: 2).map(\.number) == [5, 4])
        #expect(try sales.recent(before: 4, limit: 2).map(\.number) == [3, 2])
        #expect(try sales.recent(before: 2, limit: 2).map(\.number) == [1])
        #expect(try sales.recent(before: 1, limit: 2).isEmpty)
    }

    @Test("A sale is found by its number")
    func saleByNumber() throws {
        _ = try sell()
        let second = try sell()
        #expect(try sales.sale(number: 2)?.id == second.id)
        #expect(try sales.sale(number: 9) == nil)
    }
}
