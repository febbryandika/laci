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
        // One line always: at AX5 a wrapped "Rp3.50 / 0" reads as two amounts, so the digits shrink
        // before they ever break.
        // The label goes on the Text itself: set after the line modifiers it lands on a wrapper
        // and VoiceOver reads the spoken form and then the printed one.
        Text(verbatim: amount.formatted(MoneyFormat.rupiah))
            .accessibilityLabel(Text(verbatim: amount.formatted(MoneyFormat.spoken)))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}
