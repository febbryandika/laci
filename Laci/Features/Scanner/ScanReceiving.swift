import Foundation
import LaciCore

/// What the cashier is told when a scan adds nothing (SPEC §6): a misread and a missing product
/// are different problems, so a bad checksum says "scan again" and never "unknown product".
enum ScanNotice: Hashable {
    case scanAgain
    case lookupFailed
    /// Stocktake only: the sell screen opens the create form instead (SPEC §3.1.2).
    case unknownProduct
    /// Stocktake and adjustments only: a product nobody counts cannot be counted.
    case untrackedProduct
}

/// A screen that takes scans: the camera sheet, the keyboard wedge and manual entry all land on
/// `didRead`, whichever screen owns them (SPEC §6). Selling and stocktake share the sheet through it.
@MainActor
protocol ScanReceiving: AnyObject, Observable {
    /// Shared with the camera controller so the owner can `reset()` it after removing a row.
    var scanDebouncer: ScanDebouncer { get }
    /// Counts accepted scans; the views key haptic and audible feedback on it.
    var scansAccepted: Int { get }
    var scanNotice: ScanNotice? { get }
    /// `symbology` is nil when no camera saw the code.
    func didRead(code: String, symbology: Symbology?)
}
