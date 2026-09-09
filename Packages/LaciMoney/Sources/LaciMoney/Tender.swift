import Foundation

public struct CashSettlement: Hashable, Sendable {
    public let exact: Money, rounded: Money
    public let roundingDelta: Money // rounded − exact, signed
    public let tendered: Money, change: Money

    public init(exact: Money, rounded: Money, roundingDelta: Money, tendered: Money, change: Money) {
        self.exact = exact
        self.rounded = rounded
        self.roundingDelta = roundingDelta
        self.tendered = tendered
        self.change = change
    }
}

public enum Tender {
    public static let cashIncrement: Decimal = 100

    /// The notes a customer actually hands over.
    static let notes: [Decimal] = [1000, 2000, 5000, 10000, 20000, 50000, 100_000]

    public static func roundForCash(_ total: Money) -> Money {
        Money(Rounding.toNearest(total.amount, increment: cashIncrement))
    }

    /// nil when the tender does not cover the rounded total. A non-optional return with a negative
    /// `change` is the API that ships the bug.
    public static func settle(total: Money, tendered: Money) -> CashSettlement? {
        let rounded = roundForCash(total)
        guard tendered >= rounded else { return nil }
        return CashSettlement(
            exact: total,
            rounded: rounded,
            roundingDelta: rounded - total,
            tendered: tendered,
            change: tendered - rounded
        )
    }

    /// Quick-tender buttons: the rounded total, then the four smallest note combinations above it
    /// (1k, 2k, 5k, 10k, 20k, 50k, 100k) — what a customer actually hands over.
    public static func suggestions(for total: Money) -> [Money] {
        let rounded = roundForCash(total)
        let above = Set(notes.map { Rounding.nextMultiple(above: rounded.amount, of: $0) })
        return [rounded] + above.sorted().prefix(4).map(Money.init)
    }
}
