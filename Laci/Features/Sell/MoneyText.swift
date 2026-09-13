import Foundation
import LaciMoney
import SwiftUI

/// An on-screen amount: printed as "Rp 15.000", announced as "15.000 Rupiah Indonesia" (SPEC §9).
/// Every amount in the app goes through here, so the label can never be forgotten at a call site.
struct MoneyText: View {
    private let amount: Decimal

    init(_ money: Money) {
        amount = money.amount
    }

    init(_ amount: Decimal) {
        self.amount = amount
    }

    var body: some View {
        Text(amount, format: MoneyFormat.rupiah)
            .accessibilityLabel(Text(amount, format: MoneyFormat.spoken))
    }
}
