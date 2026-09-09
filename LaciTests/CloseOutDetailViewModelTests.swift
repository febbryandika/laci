import Foundation
@testable import Laci
import LaciCore
import LaciMoney
import Testing

@MainActor
@Suite("Close-out detail view model")
struct CloseOutDetailViewModelTests {
    let fixture: CloseOutFixture

    init() throws {
        fixture = try CloseOutFixture()
        let midday = fixture.closeOutViewModel()
        midday.addPayout(kind: .pettyCash, amountText: "5000", note: "plastik")
        // Closed an hour later, so the setoran sorts after the mid-day payout.
        let closing = fixture.closeOutViewModel(now: CloseOutFixture.now.addingTimeInterval(3600))
        fixture.count(closing, counted: "195000")
        closing.save(note: "", cashRemovedText: "150000")
    }

    func detail(of day: Date? = nil) -> CloseOutDetailViewModel {
        let viewModel = CloseOutDetailViewModel(tradingDay: day ?? fixture.day(), dependencies: fixture.dependencies)
        viewModel.load()
        return viewModel
    }

    @Test("Loading finds the saved row and reads its stored figures")
    func loadFindsTheRow() {
        let viewModel = detail()
        #expect(viewModel.closeOut?.tradingDay == fixture.day())
        #expect(viewModel.closeOut?.discrepancy == 0)
        #expect(viewModel.closeOut?.attributionKind == nil)
        #expect(!viewModel.failed)
    }

    @Test("The day's payouts are listed, the closing setoran last")
    func payoutsListed() {
        let viewModel = detail()
        #expect(viewModel.payouts.map(\.kind) == [.pettyCash, .setoran])
        #expect(viewModel.payouts.map(\.amount) == [5000, 150_000])
        #expect(viewModel.closeOut?.payouts == 5000)
    }

    @Test("A day that was never closed loads as nothing")
    func unknownDay() {
        #expect(detail(of: fixture.day(1)).closeOut == nil)
    }

    @Test("Attribution is persisted and can be cleared")
    func attributionRoundTrips() throws {
        let viewModel = detail()
        viewModel.setAttribution(.bug)
        #expect(viewModel.closeOut?.attributionKind == .bug)
        #expect(try fixture.dependencies.closeOuts.closeOut(on: fixture.day())?.attribution == "bug")
        viewModel.setAttribution(nil)
        #expect(viewModel.closeOut?.attribution == nil)
        #expect(!viewModel.failed)
    }

    @Test("Attributing a day that was never closed fails")
    func attributionNeedsRow() {
        let viewModel = detail(of: fixture.day(1))
        viewModel.setAttribution(.operatorError)
        #expect(viewModel.failed)
    }
}
