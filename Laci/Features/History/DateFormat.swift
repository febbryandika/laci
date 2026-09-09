import Foundation
import LaciCore
import SwiftUI

/// Sale times render in the shop's locale and zone, never the device's (SPEC §9): a Bandung shop
/// with an English iPad still reads its own clock.
enum DateFormat {
    static let dateTime = Date.FormatStyle(
        date: .abbreviated, time: .shortened, locale: ShopDefaults.locale, timeZone: ShopDefaults.timeZone
    )

    /// A trading day: the date alone, in the shop's zone.
    static let day = Date.FormatStyle(
        date: .long, time: .omitted, locale: ShopDefaults.locale, timeZone: ShopDefaults.timeZone
    )
}

extension Sale {
    var paymentLabel: LocalizedStringKey {
        switch paymentMethod {
        case .cash: "Tunai"
        case .qris: "QRIS"
        case .transfer: "Transfer"
        case nil: "?"
        }
    }

    var isRefund: Bool {
        refundsSaleID != nil
    }
}
