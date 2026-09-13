import Foundation

/// Everything the sell screen presents on top of itself.
enum SellSheet: Identifiable, Hashable {
    case editLine(sku: String)
    case saleDiscount
    case tender
    case scanner
    /// nil: no barcode, the catalogue's "add first product".
    case newProduct(PendingBarcode?)
    case paywall
    case importCatalogue

    var id: String {
        switch self {
        case let .editLine(sku): "line-\(sku)"
        case .saleDiscount: "discount"
        case .tender: "tender"
        case .scanner: "scanner"
        case let .newProduct(pending): "new-\(pending?.value ?? "manual")"
        case .paywall: "paywall"
        case .importCatalogue: "import"
        }
    }
}

/// The screens pushed from the sell screen. Value-based, so ⌘L and a banner can push the same
/// destination a toolbar button does.
enum SellRoute: Hashable {
    case closeOut
    case history
    case stocktake
    case settings
    case catalogue
}

/// What can hold keyboard focus on the sell screen (SPEC §9).
enum SellField: Hashable {
    case wedge
    case search
    case cart
    case tenderAmount
}
