// LaciMoney — the pure money engine (SPEC §8). Imports nothing but Foundation; a CI
// script (scripts/assert-money-imports.sh) fails the build if anything else appears.
// Domain types (Money, Discount, CartLine, Tender, CloseOutEngine) arrive in Phase 2.

import Foundation

/// Package marker: lets the smoke test prove the module builds and links under Swift 6
/// strict concurrency before any domain type exists. Not a domain type.
public enum LaciMoneyPackage {
    public static let name = "LaciMoney"
}
