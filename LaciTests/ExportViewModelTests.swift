import Foundation
@testable import Laci
import LaciCore
import LaciMoney
import Testing

/// A clock the sell screen reads on every checkout, so one fixture rings up sales on several days.
@MainActor
final class ExportClock {
    var now = CloseOutFixture.now
}

@MainActor
@Suite("Export view model")
struct ExportViewModelTests {
    let fixture: CloseOutFixture
    let defaults: UserDefaults
    let clock = ExportClock()
    let sell: SellViewModel

    init() throws {
        fixture = try CloseOutFixture()
        let suite = "ExportViewModelTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let clock = clock
        sell = SellViewModel(dependencies: fixture.dependencies, now: { clock.now })
        sell.loadCatalogue()
    }

    func makeViewModel(now: Date = CloseOutFixture.now) -> ExportViewModel {
        ExportViewModel(dependencies: fixture.dependencies, defaults: defaults, now: { now })
    }

    func ringUp(dayOffset: Int, hour: Double = 0) {
        clock.now = CloseOutFixture.now.addingTimeInterval(CloseOutFixture.oneDay * Double(dayOffset) + hour * 3600)
        sell.add(fixture.product)
        sell.checkoutCash(tendered: Money(20000))
    }

    func rows(_ text: String) -> [String] {
        Array(text.split(separator: "\n").map(String.init).dropFirst())
    }

    @Test("Sales and their lines are selected by trading day, both ends inclusive")
    func salesRangeSelectsTradingDays() throws {
        ringUp(dayOffset: 0)
        ringUp(dayOffset: 1)
        ringUp(dayOffset: 2)
        let viewModel = makeViewModel()
        viewModel.firstDay = fixture.day(0)
        viewModel.lastDay = fixture.day(1)
        #expect(try rows(viewModel.text(for: .sales)).count == 2)
        #expect(try rows(viewModel.text(for: .saleLines)).count == 2)
        viewModel.lastDay = fixture.day(2)
        #expect(try rows(viewModel.text(for: .sales)).count == 3)
    }

    @Test("Stock movements follow the cutover: 01:00 belongs to the day before")
    func movementsFollowCutover() throws {
        let stock = fixture.dependencies.stock
        try fixture.dependencies.products.create(Product(
            sku: "T", name: "Tracked", unit: "pcs", cost: 100, price: 200, tracksStock: true, stockOnHand: 1,
            updatedAt: CloseOutFixture.now
        ))
        // 15:00 WIB on day 0, 01:00 WIB on day 1 (still trading day 0), 05:00 WIB on day 1.
        let now = CloseOutFixture.now
        try stock.adjust(sku: "T", delta: 1, reason: .stockIn, occurredAt: now)
        try stock.adjust(sku: "T", delta: 2, reason: .stockIn, occurredAt: now.addingTimeInterval(10 * 3600))
        try stock.adjust(sku: "T", delta: 3, reason: .waste, occurredAt: now.addingTimeInterval(14 * 3600))
        let viewModel = makeViewModel()
        viewModel.firstDay = fixture.day(0)
        viewModel.lastDay = fixture.day(0)
        let lines = try rows(viewModel.text(for: .stockMovements))
        #expect(lines.count == 2)
        #expect(lines.allSatisfy { $0.contains(",T,") })
        #expect(lines.map { $0.split(separator: ",")[2] } == ["1", "2"])
    }

    @Test("The semicolon setting flows into every file")
    func semicolonSettingFlowsIntoOutput() throws {
        ringUp(dayOffset: 0)
        ExportSettings.save(semicolonDelimiter: true, in: defaults)
        let viewModel = makeViewModel()
        viewModel.firstDay = fixture.day(0)
        viewModel.lastDay = fixture.day(0)
        for kind in ExportKind.allCases {
            let text = try viewModel.text(for: kind)
            let header = try #require(text.split(separator: "\n").first)
            #expect(header.contains(";"), "\(kind)")
            #expect(!header.contains(","), "\(kind)")
        }
        #expect(try viewModel.text(for: .sales).contains(";12400;cash;20000;7600;"))
    }

    @Test("The file name carries the kind and the plain dates of the range")
    func filenameUsesPlainDates() {
        let viewModel = makeViewModel()
        viewModel.firstDay = fixture.day(0)
        viewModel.lastDay = fixture.day(2)
        #expect(viewModel.prepare(.closeOuts))
        #expect(viewModel.filename == "close_outs_2027-01-15_2027-01-17.csv")
        #expect(viewModel.document?.text == ExportCSV.closeOutsColumns.joined(separator: ",") + "\n")
        viewModel.clearDocument()
        #expect(viewModel.document == nil)
    }

    @Test("A range whose end precedes its start is refused before anything is read")
    func invertedRangeIsAnError() {
        let viewModel = makeViewModel()
        viewModel.firstDay = fixture.day(2)
        viewModel.lastDay = fixture.day(0)
        #expect(!viewModel.prepare(.sales))
        #expect(viewModel.error == .rangeInverted)
        #expect(viewModel.document == nil)
    }

    @Test("The default range is the first of the month through today, in the shop's zone")
    func defaultRangeIsMonthToDate() throws {
        let viewModel = makeViewModel()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ShopDefaults.timeZone
        let first = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 1)))
        #expect(viewModel.firstDay == first)
        #expect(viewModel.lastDay == fixture.day(0))
        // 02:00 WIB on the 16th is still trading day the 15th.
        let early = makeViewModel(now: CloseOutFixture.now.addingTimeInterval(11 * 3600))
        #expect(early.lastDay == fixture.day(0))
    }

    @Test("A close-out in range is exported with its stored figures")
    func closeOutsExported() throws {
        try fixture.dependencies.closeOuts.save(CloseOut(
            tradingDay: fixture.day(0), openingFloat: 200_000, cashSales: 12400, cashRefunds: 0, payouts: 0,
            expectedDrawer: 212_400, countedDrawer: 212_400, discrepancy: 0, note: nil,
            closedAt: CloseOutFixture.now, attribution: nil
        ), cashRemoved: 0)
        let viewModel = makeViewModel()
        viewModel.firstDay = fixture.day(0)
        viewModel.lastDay = fixture.day(0)
        let lines = try rows(viewModel.text(for: .closeOuts))
        #expect(lines == ["2027-01-15,200000,12400,0,0,212400,212400,0,,2027-01-15T15:00:00+07:00,"])
    }
}
