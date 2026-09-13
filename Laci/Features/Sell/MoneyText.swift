import Foundation
import LaciMoney
import SwiftUI

/// An on-screen amount: printed as "Rp 15.000", announced as "15.000 rupiah" (SPEC §9).
/// Every amount in the app goes through here, so the label can never be forgotten at a call site.
/// Both strings are formatted before they reach `Text`: `Text(_:format:)` re-applies the
/// environment locale to a style, and a Japanese iPad must still print the shop's rupiah.
struct MoneyText: View {
    private let amount: Decimal

    init(_ money: Money) {
        amount = money.amount
    }

    init(_ amount: Decimal) {
        self.amount = amount
    }

    var body: some View {
        Text(verbatim: amount.formatted(MoneyFormat.rupiah))
            .accessibilityLabel(Text(verbatim: amount.formatted(MoneyFormat.spoken)))
    }
}
