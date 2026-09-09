import Foundation
import LaciCore
import LaciMoney

/// Shop-level settings that Phase 4 hardcodes. They move to the Settings feature later; nothing
/// else in the app may read `TimeZone.current` or pick a tax policy on its own.
enum ShopDefaults {
    /// A sale rung up at 1am belongs to the previous trading day (SPEC §4).
    static let tradingDay = TradingDay(cutoverHour: 4)
    /// The identifier is in every tz database, so the fallback is theoretical.
    static let timeZone = TimeZone(identifier: "Asia/Jakarta") ?? .current
    /// Most one-outlet warung are not PKP and print no tax line (SPEC §8.2).
    static let taxPolicy = TaxPolicy.nonPKP
    /// On-screen money is Indonesian regardless of the device locale (SPEC §9).
    static let locale = Locale(identifier: "id_ID")
    /// A close-out discrepancy beyond this needs a note before it can be saved (SPEC §3.3.3).
    static let discrepancyThreshold = Money(5000)
}
