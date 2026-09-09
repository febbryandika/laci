import Foundation

/// Every rounding decision in the package goes through here, so the policy in SPEC §8.3 has one home.
public enum Rounding {
    /// Banker's rounding (half to even) to `scale` decimal places. Line and sale arithmetic.
    public static func bankers(_ value: Decimal, scale: Int) -> Decimal {
        round(value, scale: scale, mode: .bankers)
    }

    /// Nearest multiple of `increment`, half away from zero: 12 350 → 12 400, −12 350 → −12 400.
    /// Cash tender only (SPEC §8.3).
    public static func toNearest(_ value: Decimal, increment: Decimal) -> Decimal {
        round(value / increment, scale: 0, mode: .plain) * increment
    }

    /// Smallest multiple of `step` strictly greater than `value`.
    static func nextMultiple(above value: Decimal, of step: Decimal) -> Decimal {
        round(value / step, scale: 0, mode: .down) * step + step
    }

    private static func round(_ value: Decimal, scale: Int, mode: NSDecimalNumber.RoundingMode) -> Decimal {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, mode)
        return result
    }
}
