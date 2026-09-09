import Foundation
@testable import Laci
import LaciCore
import LaciMoney
import Testing

private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

/// SPEC §3.3.5: an earlier day that was never closed banners on the sell screen.
@MainActor
@Suite("Sell screen close-out banner")
struct SellCloseOutBannerTests {
    let dependencies: Dependencies

    init() throws {
        dependencies = try Dependencies.inMemory()
    }

    func close(day offset: Int) {
        let instant = fixedNow.addingTimeInterval(86400 * Double(offset))
        let closing = CloseOutViewModel(dependencies: dependencies, now: { instant })
        closing.load()
        closing.openingFloatText = "0"
        closing.countedText = "0"
        closing.enterCount()
        closing.save(note: "", cashRemovedText: "")
    }

    func sell(daysLater offset: Int) -> SellViewModel {
        let instant = fixedNow.addingTimeInterval(86400 * Double(offset))
        let viewModel = SellViewModel(dependencies: dependencies, now: { instant })
        viewModel.refreshCloseOutStatus()
        return viewModel
    }

    @Test("No open prior day is reported before any close-out, or when yesterday was closed")
    func noOpenPriorDay() {
        #expect(sell(daysLater: 0).openPriorDay == nil)
        close(day: 0)
        #expect(sell(daysLater: 0).openPriorDay == nil)
        #expect(sell(daysLater: 1).openPriorDay == nil)
    }

    @Test("The first unclosed day after the last close-out is reported until it is closed")
    func openPriorDayIsReported() {
        close(day: 0)
        let expected = ShopDefaults.tradingDay.bucket(
            for: fixedNow.addingTimeInterval(86400), timeZone: ShopDefaults.timeZone
        )
        #expect(sell(daysLater: 2).openPriorDay == expected)
        close(day: 1)
        #expect(sell(daysLater: 2).openPriorDay == nil)
    }
}
