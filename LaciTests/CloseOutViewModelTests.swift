import Foundation
@testable import Laci
import LaciCore
import LaciMoney
import Testing

@MainActor
@Suite("Close-out view model")
struct CloseOutViewModelTests {
    let fixture: CloseOutFixture

    init() throws {
        fixture = try CloseOutFixture()
    }

    // MARK: Expected-figure gating

    @Test("Before a count is confirmed there is no expected figure to show")
    func nothingToRevealBeforeCount() throws {
        try fixture.ringUpCash()
        let viewModel = fixture.closeOutViewModel()
        #expect(viewModel.inputs == nil)
        #expect(viewModel.result == nil)
        #expect(viewModel.closeOut == nil)
        #expect(viewModel.needsOpeningFloat)
        #expect(!viewModel.isPriorDay)
        #expect(viewModel.targetDay == fixture.day())
    }

    @Test("Confirming the count reveals the figures; changing it hides them again")
    func confirmThenChange() throws {
        try fixture.ringUpCash()
        let viewModel = fixture.closeOutViewModel()
        fixture.count(viewModel, counted: "212400")
        #expect(viewModel.inputs != nil)
        #expect(viewModel.result?.discrepancy == .zero)
        viewModel.changeCount()
        #expect(viewModel.inputs == nil)
        #expect(viewModel.result == nil)
    }

    @Test("A count that is not a number, or a first day without a float, is refused")
    func invalidCount() {
        let viewModel = fixture.closeOutViewModel()
        viewModel.countedText = "abc"
        viewModel.openingFloatText = "200000"
        viewModel.enterCount()
        #expect(viewModel.error == .countInvalid)
        viewModel.countedText = "200000"
        viewModel.openingFloatText = ""
        viewModel.enterCount()
        #expect(viewModel.error == .openingFloatRequired)
        #expect(viewModel.result == nil)
    }

    // MARK: Reconcile inputs

    @Test("Cash sales are the rounded totals, and expected comes from the engine")
    func cashSalesAreRounded() throws {
        try fixture.ringUpCash()
        let viewModel = fixture.closeOutViewModel()
        fixture.count(viewModel, counted: "212400")
        let inputs = try #require(viewModel.inputs)
        #expect(inputs.openingFloat == Money(200_000))
        #expect(inputs.cashSales == Money(12400))
        #expect(inputs.cashRefunds == .zero)
        #expect(inputs.payouts == .zero)
        #expect(viewModel.result == CloseOutEngine.reconcile(inputs, counted: Money(212_400)))
        #expect(viewModel.result?.expected == Money(212_400))
    }

    @Test("A cash refund is a separate input that lowers the expected drawer")
    func cashRefundLowersExpected() throws {
        let sale = try fixture.ringUpCash()
        try fixture.ringUpCash()
        let detail = SaleDetailViewModel(
            saleID: sale.id, dependencies: fixture.dependencies, now: { CloseOutFixture.now }
        )
        detail.load()
        detail.refund()
        let viewModel = fixture.closeOutViewModel()
        fixture.count(viewModel, counted: "212400")
        #expect(viewModel.inputs?.cashSales == Money(24800))
        #expect(viewModel.inputs?.cashRefunds == Money(12400))
        #expect(viewModel.result?.expected == Money(212_400))
    }

    // MARK: Payouts

    @Test("A payout is stored for the day, subtracts from expected, and clears a confirmed count")
    func payoutSubtracts() throws {
        try fixture.ringUpCash()
        let viewModel = fixture.closeOutViewModel()
        fixture.count(viewModel, counted: "142400")
        viewModel.addPayout(kind: .supplier, amountText: "70000", note: "Indomie 2 dus")
        #expect(viewModel.error == nil)
        #expect(viewModel.payouts.map(\.amount) == [70000])
        #expect(viewModel.payouts.first?.kind == .supplier)
        #expect(viewModel.result == nil)
        fixture.count(viewModel, counted: "142400")
        #expect(viewModel.inputs?.payouts == Money(70000))
        #expect(viewModel.result?.expected == Money(142_400))
        #expect(try fixture.dependencies.closeOuts.payouts(on: fixture.day()).count == 1)
    }

    @Test("A payout needs a positive amount and a note")
    func payoutValidation() {
        let viewModel = fixture.closeOutViewModel()
        viewModel.addPayout(kind: .pettyCash, amountText: "5000", note: "  ")
        #expect(viewModel.error == .noteRequired)
        viewModel.addPayout(kind: .pettyCash, amountText: "0", note: "plastik")
        #expect(viewModel.error == .amountInvalid)
        viewModel.addPayout(kind: .pettyCash, amountText: "x", note: "plastik")
        #expect(viewModel.error == .amountInvalid)
        #expect(viewModel.payouts.isEmpty)
    }

    @Test("Deleting a payout removes it and clears a confirmed count")
    func deletePayout() throws {
        let viewModel = fixture.closeOutViewModel()
        viewModel.addPayout(kind: .pettyCash, amountText: "5000", note: "plastik")
        fixture.count(viewModel, counted: "195000")
        let payout = try #require(viewModel.payouts.first)
        viewModel.deletePayout(payout)
        #expect(viewModel.payouts.isEmpty)
        #expect(viewModel.result == nil)
    }

    // MARK: Sequence

    @Test("Tomorrow's float is counted minus the setoran, and a day with no sales still closes")
    func carryForward() throws {
        let today = fixture.closeOutViewModel()
        fixture.count(today, float: "250000", counted: "250000")
        today.save(note: "", cashRemovedText: "200000")
        #expect(today.error == nil)
        #expect(try fixture.dependencies.closeOuts.payouts(on: fixture.day()).map(\.kind) == [.setoran])

        let tomorrow = fixture.closeOutViewModel(now: CloseOutFixture.now.addingTimeInterval(CloseOutFixture.oneDay))
        #expect(tomorrow.targetDay == fixture.day(1))
        #expect(!tomorrow.needsOpeningFloat)
        #expect(!tomorrow.isPriorDay)
        #expect(tomorrow.latestClosed?.tradingDay == fixture.day())
        tomorrow.countedText = "50000"
        tomorrow.enterCount()
        #expect(tomorrow.inputs?.openingFloat == Money(50000))
        #expect(tomorrow.inputs?.cashSales == .zero)
        #expect(tomorrow.result?.expected == Money(50000))
        #expect(tomorrow.result?.discrepancy == .zero)
    }

    @Test("An unclosed earlier day is the one the screen closes")
    func priorDayIsTarget() {
        let today = fixture.closeOutViewModel()
        fixture.count(today, counted: "200000")
        today.save(note: "", cashRemovedText: "")

        let later = fixture.closeOutViewModel(now: CloseOutFixture.now.addingTimeInterval(2 * CloseOutFixture.oneDay))
        #expect(later.targetDay == fixture.day(1))
        #expect(later.isPriorDay)
        #expect(later.closeOut == nil)
    }

    @Test("The target-day rule", arguments: [
        (nil as Int?, 0), (0, 0), (-1, 0), (-3, -2),
    ])
    func targetDayRule(latestOffset: Int?, expectedOffset: Int) {
        let latest = latestOffset.map { fixture.day($0) }
        #expect(CloseOutViewModel.targetDay(latest: latest, today: fixture.day()) == fixture.day(expectedOffset))
    }
}
