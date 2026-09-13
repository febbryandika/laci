import SwiftUI

/// SPEC §9: three panes on an iPad, two once Dynamic Type reaches AX3, and on an iPhone the cart
/// is the screen with the catalogue and the keypad as sheets. Regular width and height together
/// mean a full-width iPad; an iPhone in landscape and an iPad in Slide Over take the iPhone layout.
enum SellLayout: Hashable {
    case threePane
    case twoPane
    case compact

    static func resolve(
        horizontal: UserInterfaceSizeClass?, vertical: UserInterfaceSizeClass?, dynamicTypeSize: DynamicTypeSize
    ) -> SellLayout {
        guard horizontal == .regular, vertical == .regular else { return .compact }
        return dynamicTypeSize >= .accessibility3 ? .twoPane : .threePane
    }

    /// The catalogue grid; otherwise the search results live in the cart list.
    var showsCataloguePane: Bool {
        self == .threePane
    }

    /// The tender keypad beside the cart; otherwise it is a sheet behind the Bayar button.
    var showsTenderPane: Bool {
        self != .compact
    }
}
