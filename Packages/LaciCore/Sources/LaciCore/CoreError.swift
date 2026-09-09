import Foundation

/// The business failures a repository can report. SwiftData's own errors pass through untyped.
public enum CoreError: Error, Hashable, Sendable {
    case skuTaken(String)
    case productNotFound(sku: String)
    case barcodeTaken(value: String, existingSKU: String)
    case dayAlreadyClosed(tradingDay: Date)
    /// Attribution is set on a saved close-out; there is nothing to attribute before one exists.
    case closeOutNotFound(tradingDay: Date)
    case emptySale
    /// The cash settlement was computed for a different total than the draft carries.
    case settlementMismatch
    case saleNotFound(id: UUID)
    /// Void and refund both refuse a voided sale.
    case saleAlreadyVoided(id: UUID)
    case voidReasonRequired
    /// A sale with a non-voided refund can be neither voided nor refunded again.
    case saleHasLiveRefund(id: UUID)
    /// A refund is corrected by voiding it, never by refunding it.
    case saleIsRefund(id: UUID)
}
