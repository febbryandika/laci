import Foundation

/// Everything the sell screen presents on top of itself.
enum SellSheet: Identifiable, Hashable {
    case editLine(sku: String)
    case saleDiscount
    case tender
    case scanner
    case newProduct(PendingBarcode)
    case paywall

    var id: String {
        switch self {
        case let .editLine(sku): "line-\(sku)"
        case .saleDiscount: "discount"
        case .tender: "tender"
        case .scanner: "scanner"
        case let .newProduct(pending): "new-\(pending.value)"
        case .paywall: "paywall"
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
}

/// What can hold keyboard focus on the sell screen (SPEC §9).
enum SellField: Hashable {
    case wedge
    case search
    case cart
    case tenderAmount
}
