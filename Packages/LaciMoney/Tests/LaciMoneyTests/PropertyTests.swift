@testable import LaciMoney

// swiftlint:disable identifier_name
import Foundation
import Testing

struct Seeded: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17; return state
    }
}

private func randomLines(_ g: inout Seeded, count: Int) -> [CartLine] {
    (0 ..< count).map { i in
        CartLine(sku: "S\(i)", name: "Item \(i)",
                 quantity: Decimal(Int.random(in: 1 ... 12, using: &g)),
                 unitPrice: Money(Decimal(Int.random(in: 500 ... 250_000, using: &g))),
                 discount: Bool.random(using: &g)
                     ? .percent(Decimal(Int.random(in: 0 ... 30, using: &g)))
                     : .amount(Money(Decimal(Int.random(in: 0 ... 5000, using: &g)))),
                 taxable: true)
    }
}

@Test("Change is never negative, and rounding is reversible and bounded", arguments: 0 ..< 500)
func cashSettlementInvariants(seed: Int) throws {
    var g = Seeded(state: UInt64(seed) &+ 0x9E37_79B9)
    let t = Pricing.totals(lines: randomLines(&g, count: Int.random(in: 1 ... 15, using: &g)),
                           saleDiscount: .none, tax: .nonPKP)
    let tendered = Money(Tender.roundForCash(t.grandTotal).amount
        + Decimal(Int.random(in: 0 ... 200_000, using: &g)))
    let s = try #require(Tender.settle(total: t.grandTotal, tendered: tendered))
    #expect(s.change >= .zero, "seed \(seed)")
    #expect(s.tendered - s.change == s.rounded, "seed \(seed)")
    #expect(s.rounded - s.roundingDelta == s.exact, "seed \(seed)")
    #expect(abs(s.roundingDelta.amount) <= 50, "seed \(seed): moved by \(s.roundingDelta.amount)")
}

@Test("Drawer reconciles exactly when nothing is miscounted", arguments: 0 ..< 500)
func drawerReconciles(seed: Int) {
    var g = Seeded(state: UInt64(seed) &+ 7)
    let sales = (0 ..< Int.random(in: 1 ... 40, using: &g)).map { _ -> Money in
        let t = Pricing.totals(lines: randomLines(&g, count: Int.random(in: 1 ... 6, using: &g)),
                               saleDiscount: .none, tax: .nonPKP)
        return Tender.roundForCash(t.grandTotal) // rounded: what enters the drawer
    }
    let i = DrawerInputs(openingFloat: Money(200_000), cashSales: sales.reduce(.zero, +),
                         cashRefunds: .zero,
                         payouts: Money(Decimal(Int.random(in: 0 ... 150_000, using: &g))))
    #expect(CloseOutEngine.reconcile(i, counted: i.openingFloat + i.cashSales - i.payouts)
        .discrepancy == .zero, "seed \(seed)")
}

@Test("Inclusive PPN: taxable base plus tax reconstructs the gross exactly", arguments: 0 ..< 500)
func inclusiveTaxReconstructs(seed: Int) {
    var g = Seeded(state: UInt64(seed) &+ 11)
    let t = Pricing.totals(lines: randomLines(&g, count: Int.random(in: 1 ... 20, using: &g)),
                           saleDiscount: .percent(Decimal(Int.random(in: 0 ... 15, using: &g))),
                           tax: TaxPolicy(mode: .inclusive, rate: 0.11))
    #expect(t.taxable + t.tax == t.grandTotal, "seed \(seed)")
}

/// The verbatim test above derives `counted` from `cashSales`, so it cannot tell rounded from exact
/// sums. Here the drawer is counted from the physical rounded cash, independently of the inputs, and
/// summing exact totals into `cashSales` (the SPEC §8.4 bug) makes it short on most seeds.
@Test("Drawer reconciles only when cashSales sums the rounded totals", arguments: 0 ..< 500)
func drawerHoldsRoundedCash(seed: Int) {
    var g = Seeded(state: UInt64(seed) &+ 13)
    let exact = (0 ..< Int.random(in: 1 ... 40, using: &g)).map { _ -> Money in
        Pricing.totals(lines: randomLines(&g, count: Int.random(in: 1 ... 6, using: &g)),
                       saleDiscount: .none, tax: .nonPKP).grandTotal
    }
    let rounded = exact.map(Tender.roundForCash)
    let drawer = Money(200_000) + rounded.reduce(.zero, +) // what is physically in the till
    let i = DrawerInputs(openingFloat: Money(200_000), cashSales: rounded.reduce(.zero, +),
                         cashRefunds: .zero, payouts: .zero)
    #expect(CloseOutEngine.reconcile(i, counted: drawer).discrepancy == .zero, "seed \(seed)")
}

// swiftlint:enable identifier_name
