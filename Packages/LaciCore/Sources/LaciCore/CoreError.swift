import Foundation

/// The business failures a repository can report. SwiftData's own errors pass through untyped.
public enum CoreError: Error, Hashable, Sendable {
    case skuTaken(String)
    case productNotFound(sku: String)
    case barcodeTaken(value: String, existingSKU: String)
    case dayAlreadyClosed(tradingDay: Date)
    case emptySale
    /// The cash settlement was computed for a different total than the draft carries.
    case settlementMismatch
}
