import Foundation

public struct DrawerInputs: Hashable, Sendable {
    public let openingFloat: Money
    public let cashSales: Money // Σ ROUNDED totals of non-voided cash sales that day
    public let cashRefunds: Money
    public let payouts: Money // supplier paid from the till, setoran, petty cash

    public init(openingFloat: Money, cashSales: Money, cashRefunds: Money, payouts: Money) {
        self.openingFloat = openingFloat
        self.cashSales = cashSales
        self.cashRefunds = cashRefunds
        self.payouts = payouts
    }
}

public struct DrawerResult: Hashable, Sendable {
    public let expected: Money, counted: Money
    public let discrepancy: Money // counted − expected. Negative is short.
    public var isShort: Bool {
        discrepancy < .zero
    }

    public init(expected: Money, counted: Money, discrepancy: Money) {
        self.expected = expected
        self.counted = counted
        self.discrepancy = discrepancy
    }
}

public enum CloseOutEngine {
    /// expected = openingFloat + cashSales − cashRefunds − payouts
    public static func reconcile(_ inputs: DrawerInputs, counted: Money) -> DrawerResult {
        let expected = inputs.openingFloat + inputs.cashSales - inputs.cashRefunds - inputs.payouts
        return DrawerResult(expected: expected, counted: counted, discrepancy: counted - expected)
    }
}
