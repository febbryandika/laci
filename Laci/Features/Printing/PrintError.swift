import Foundation

/// Why a print did not happen. Every case ends the same way for the cashier: the sale is saved and
/// the struk can be reprinted (SPEC §7.3). The wording lives in the views.
nonisolated enum PrintError: Error, Hashable, Sendable {
    case bluetoothUnavailable
    case bluetoothOff
    case notConnected
    case notFound
    case busy
    case paperOut
    case saleNotFound
    /// A CoreBluetooth error, carried as text because the `NSError` is not `Sendable`.
    case transport(String)
}
