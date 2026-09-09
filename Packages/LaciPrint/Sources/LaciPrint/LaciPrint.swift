// LaciPrint — turns a Receipt into ESC/POS Data (SPEC §7). Deliberately does not import
// CoreBluetooth: the BLE transport lives in the app target. Builder, codepage, renderer
// and bitmap types arrive in a later phase.

import Foundation

/// Package marker: lets the smoke test prove the module builds and links under Swift 6
/// strict concurrency before any real type exists.
public enum LaciPrintPackage {
    public static let name = "LaciPrint"
}
