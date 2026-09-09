import Foundation
@testable import Laci
import LaciCore
import LaciMoney
import Testing

/// The store, one product and the sell screen the close-out suites ring sales through.
@MainActor
struct CloseOutFixture {
    /// 15:00 WIB on 15 Jan 2027, a fixed clock; later days are whole multiples of a day after it.
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let oneDay: TimeInterval = 86400

    let dependencies: Dependencies
    let sell: SellViewModel
    let product: Product

    init() throws {
        dependencies = try Dependencies.inMemory()
        product = Product(
            sku: "A", name: "Item A", unit: "pcs", cost: 0, price: 12350, tracksStock: false, updatedAt: Self.now
        )
        try dependencies.products.create(product)
        sell = SellViewModel(dependencies: dependencies, now: { Self.now })
        sell.loadCatalogue()
    }

    /// A cash sale whose exact total (12 350) differs from what enters the drawer (12 400).
    @discardableResult
    func ringUpCash() throws -> Sale {
        sell.add(product)
        sell.checkoutCash(tendered: Money(20000))
        return try #require(sell.lastSale)
    }

    func closeOutViewModel(
        now: Date = CloseOutFixture.now, threshold: Money = ShopDefaults.discrepancyThreshold
    ) -> CloseOutViewModel {
        let viewModel = CloseOutViewModel(dependencies: dependencies, now: { now }, threshold: threshold)
        viewModel.load()
        return viewModel
    }

    /// First day: the cashier enters the float, then counts.
    func count(_ viewModel: CloseOutViewModel, float: String = "200000", counted: String) {
        viewModel.openingFloatText = float
        viewModel.countedText = counted
        viewModel.enterCount()
    }

    func day(_ offset: Int = 0) -> Date {
        let instant = Self.now.addingTimeInterval(Self.oneDay * Double(offset))
        return ShopDefaults.tradingDay.bucket(for: instant, timeZone: ShopDefaults.timeZone)
    }
}
