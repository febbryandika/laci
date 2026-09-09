import Foundation
@testable import Laci
import LaciCore
import LaciMoney
import Testing

private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor
@Suite("Sale detail view model")
struct SaleDetailViewModelTests {
    let dependencies: Dependencies
    let sale: Sale

    init() throws {
        dependencies = try Dependencies.inMemory()
        let product = Product(
            sku: "A", name: "Item A", unit: "pcs", cost: 0, price: 12350, tracksStock: true, stockOnHand: 10,
            updatedAt: fixedNow
        )
        try dependencies.products.create(product)
        let sell = SellViewModel(dependencies: dependencies, now: { fixedNow })
        sell.loadCatalogue()
        sell.add(product)
        sell.checkoutCash(tendered: Money(20000))
        sale = try #require(sell.lastSale)
    }

    func detail(of id: UUID? = nil) -> SaleDetailViewModel {
        let viewModel = SaleDetailViewModel(saleID: id ?? sale.id, dependencies: dependencies, now: { fixedNow })
        viewModel.load()
        return viewModel
    }

    var stock: Decimal? {
        get throws { try dependencies.products.product(sku: "A")?.stockOnHand }
    }

    @Test("Loading finds the sale and offers void and refund")
    func loadFindsTheSale() {
        let viewModel = detail()
        #expect(viewModel.sale?.id == sale.id)
        #expect(viewModel.refunds.isEmpty)
        #expect(viewModel.refundedSale == nil)
        #expect(viewModel.canVoid)
        #expect(viewModel.canRefund)
        #expect(viewModel.error == nil)
    }

    @Test("An unknown sale loads as nothing and offers no action")
    func unknownSale() {
        let viewModel = detail(of: UUID())
        #expect(viewModel.sale == nil)
        #expect(!viewModel.canVoid)
        #expect(!viewModel.canRefund)
    }

    // MARK: Void

    @Test("A blank reason is refused in the view model and nothing reaches the store")
    func blankReasonIsRefused() throws {
        let viewModel = detail()
        viewModel.void(reason: "   ")
        #expect(viewModel.error == .reasonRequired)
        #expect(sale.voidedAt == nil)
        #expect(try stock == 9)
    }

    @Test("A void marks the sale at the clock's time and restores stock")
    func voidMarksAndRestores() throws {
        let viewModel = detail()
        viewModel.void(reason: "salah input")
        #expect(viewModel.error == nil)
        #expect(viewModel.sale?.voidedAt == fixedNow)
        #expect(viewModel.sale?.voidReason == "salah input")
        #expect(!viewModel.canVoid)
        #expect(!viewModel.canRefund)
        #expect(try stock == 10)
    }

    @Test("A second void is reported as already voided")
    func doubleVoid() throws {
        let viewModel = detail()
        viewModel.void(reason: "salah input")
        viewModel.void(reason: "lagi")
        #expect(viewModel.error == .alreadyVoided)
        #expect(viewModel.sale?.voidReason == "salah input")
        #expect(try stock == 10)
        viewModel.clearError()
        #expect(viewModel.error == nil)
    }

    // MARK: Refund

    @Test("A refund creates the linked sale with negative quantities and closes both actions")
    func refundCreatesLinkedSale() throws {
        let viewModel = detail()
        viewModel.refund()
        #expect(viewModel.error == nil)
        let refund = try #require(viewModel.lastRefund)
        #expect(refund.refundsSaleID == sale.id)
        #expect(refund.lines.map(\.quantity) == [-1])
        #expect(refund.total == -12400)
        #expect(refund.occurredAt == fixedNow)
        #expect(viewModel.refunds.map(\.id) == [refund.id])
        #expect(!viewModel.canRefund)
        #expect(!viewModel.canVoid)
        #expect(try stock == 10)
    }

    @Test("A voided sale cannot be refunded")
    func refundAfterVoid() throws {
        let viewModel = detail()
        viewModel.void(reason: "salah input")
        viewModel.refund()
        #expect(viewModel.error == .alreadyVoided)
        #expect(viewModel.lastRefund == nil)
        #expect(try dependencies.sales.nextNumber() == 2)
    }

    @Test("A second refund is reported as already refunded")
    func secondRefund() throws {
        let viewModel = detail()
        viewModel.refund()
        viewModel.refund()
        #expect(viewModel.error == .hasRefund)
        #expect(try dependencies.sales.nextNumber() == 3)
    }

    @Test("A refund's detail points back at the original and cannot be refunded again")
    func refundDetail() throws {
        detail().refund()
        let refund = try #require(dependencies.sales.refunds(of: sale.id).first)
        let viewModel = detail(of: refund.id)
        #expect(viewModel.refundedSale?.id == sale.id)
        #expect(!viewModel.canRefund)
        #expect(viewModel.canVoid)
        viewModel.refund()
        #expect(viewModel.error == .isRefund)
    }
}
