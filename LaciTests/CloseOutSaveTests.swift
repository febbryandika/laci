import Foundation
@testable import Laci
import LaciCore
import LaciMoney
import Testing

@MainActor
@Suite("Close-out save")
struct CloseOutSaveTests {
    let fixture: CloseOutFixture

    init() throws {
        fixture = try CloseOutFixture()
    }

    // MARK: Threshold

    @Test("A discrepancy at the threshold saves without a note")
    func thresholdNote() throws {
        try fixture.ringUpCash()
        let viewModel = fixture.closeOutViewModel()
        fixture.count(viewModel, counted: "207400")
        #expect(viewModel.result?.discrepancy == Money(-5000))
        viewModel.save(note: "", cashRemovedText: "")
        #expect(viewModel.error == nil)
        #expect(viewModel.closeOut?.discrepancy == -5000)
    }

    @Test("One rupiah over the threshold, a blank or whitespace note is refused and nothing is saved")
    func overThresholdNeedsNote() throws {
        try fixture.ringUpCash()
        let viewModel = fixture.closeOutViewModel()
        fixture.count(viewModel, counted: "207399")
        viewModel.save(note: "", cashRemovedText: "")
        #expect(viewModel.error == .noteRequired)
        viewModel.save(note: " \n", cashRemovedText: "")
        #expect(viewModel.error == .noteRequired)
        #expect(viewModel.closeOut == nil)
        #expect(try fixture.dependencies.closeOuts.latest() == nil)
        viewModel.save(note: " kurang Rp 5.001 ", cashRemovedText: "")
        #expect(viewModel.error == nil)
        #expect(viewModel.closeOut?.note == "kurang Rp 5.001")
        #expect(viewModel.closeOut?.discrepancy == -5001)
    }

    @Test("The threshold is configurable")
    func customThreshold() throws {
        try fixture.ringUpCash()
        let viewModel = fixture.closeOutViewModel(threshold: Money(1000))
        fixture.count(viewModel, counted: "211000")
        viewModel.save(note: "", cashRemovedText: "")
        #expect(viewModel.error == .noteRequired)
    }

    // MARK: Save

    @Test("Saving stores the engine's figures as they were shown, and shows the closed day")
    func saveStoresShownFigures() throws {
        try fixture.ringUpCash()
        let viewModel = fixture.closeOutViewModel()
        fixture.count(viewModel, counted: "212400")
        let result = try #require(viewModel.result)
        viewModel.save(note: "", cashRemovedText: "")
        let saved = try #require(viewModel.closeOut)
        #expect(saved.tradingDay == fixture.day())
        #expect(saved.openingFloat == 200_000)
        #expect(saved.cashSales == 12400)
        #expect(saved.cashRefunds == 0)
        #expect(saved.payouts == 0)
        #expect(saved.expectedDrawer == result.expected.amount)
        #expect(saved.countedDrawer == 212_400)
        #expect(saved.discrepancy == result.discrepancy.amount)
        #expect(saved.note == nil)
        #expect(saved.closedAt == CloseOutFixture.now)
        #expect(saved.attribution == nil)
        #expect(fixture.closeOutViewModel().closeOut?.tradingDay == fixture.day())
    }

    @Test("Saving without a confirmed count is refused")
    func saveNeedsCount() {
        let viewModel = fixture.closeOutViewModel()
        viewModel.save(note: "", cashRemovedText: "")
        #expect(viewModel.error == .countRequired)
    }

    @Test("Cash removed cannot exceed the count, and must be a number")
    func cashRemovedValidation() {
        let viewModel = fixture.closeOutViewModel()
        fixture.count(viewModel, counted: "200000")
        viewModel.save(note: "", cashRemovedText: "200001")
        #expect(viewModel.error == .cashRemovedExceedsCount)
        viewModel.save(note: "", cashRemovedText: "x")
        #expect(viewModel.error == .amountInvalid)
        #expect(viewModel.closeOut == nil)
    }

    @Test("A second close-out of the same day is rejected")
    func doubleClose() throws {
        let first = fixture.closeOutViewModel()
        let second = fixture.closeOutViewModel()
        fixture.count(first, counted: "200000")
        fixture.count(second, counted: "200000")
        first.save(note: "", cashRemovedText: "")
        second.save(note: "", cashRemovedText: "")
        #expect(second.error == .alreadyClosed)
        #expect(try fixture.dependencies.closeOuts.payouts(on: fixture.day()).isEmpty)
    }

    @Test("Figures that moved after the count was confirmed refuse to save")
    func staleFigures() throws {
        try fixture.ringUpCash()
        let viewModel = fixture.closeOutViewModel()
        fixture.count(viewModel, counted: "212400")
        try fixture.ringUpCash()
        viewModel.save(note: "", cashRemovedText: "")
        #expect(viewModel.error == .figuresChanged)
        #expect(viewModel.result == nil)
        #expect(viewModel.closeOut == nil)
    }
}
