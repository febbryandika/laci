import Foundation
import LaciCore
import LaciMoney

/// The keyboard's view of the cart (SPEC §9): one selected line that the arrow keys move and that
/// +, − and ⌘⌫ act on. Every change to the cart itself goes through the cart methods, so the
/// debouncer reset and the quantity floor are inherited, never repeated.
extension SellViewModel {
    var selectedLine: SaleDraft.Line? {
        selectedSKU.flatMap(line(sku:))
    }

    /// A SKU not in the cart is ignored; nil deselects.
    func select(sku: String?) {
        guard let sku else {
            selectedSKU = nil
            return
        }
        if line(sku: sku) != nil {
            selectedSKU = sku
        }
    }

    /// Nothing selected starts at the first line; the last line stays selected.
    func selectNext() {
        moveSelection(by: 1, from: lines.first)
    }

    /// Nothing selected starts at the last line; the first line stays selected.
    func selectPrevious() {
        moveSelection(by: -1, from: lines.last)
    }

    func removeSelected() {
        guard let selectedSKU else { return }
        remove(sku: selectedSKU)
    }

    func incrementSelected() {
        guard let selectedSKU else { return }
        increment(sku: selectedSKU)
    }

    func decrementSelected() {
        guard let selectedSKU else { return }
        decrement(sku: selectedSKU)
    }

    private func moveSelection(by offset: Int, from start: SaleDraft.Line?) {
        guard let index = lines.firstIndex(where: { $0.cart.sku == selectedSKU }) else {
            selectedSKU = start?.cart.sku
            return
        }
        let target = index + offset
        guard lines.indices.contains(target) else { return }
        selectedSKU = lines[target].cart.sku
    }
}
