import Foundation
import LaciCore
import Observation

/// The two manual movements (SPEC §1 non-goals: stock arrives as a manual adjustment; there is no
/// purchase order). Waste is entered as a positive quantity and written as a negative delta.
enum AdjustmentKind: String, CaseIterable, Hashable, Identifiable {
    case stockIn
    case waste

    var id: String {
        rawValue
    }

    var reason: MovementReason {
        switch self {
        case .stockIn: .stockIn
        case .waste: .waste
        }
    }
}

enum StockAdjustmentError: Hashable {
    case productNotFound
    case untracked
    case quantityInvalid
    case failed
}

@MainActor
@Observable
final class StockAdjustmentViewModel {
    struct Saved: Hashable {
        let sku: String
        let delta: Decimal
        let stockOnHand: Decimal
    }

    var skuText = ""
    var kind: AdjustmentKind = .stockIn
    var quantityText = ""
    var note = ""
    private(set) var product: Product?
    private(set) var error: StockAdjustmentError?
    private(set) var saved: Saved?

    private let products: any ProductRepository
    private let stock: any StockRepository
    private let now: () -> Date

    init(dependencies: Dependencies, now: @escaping () -> Date = { Date() }) {
        products = dependencies.products
        stock = dependencies.stock
        self.now = now
    }

    /// A SKU first, then a barcode: the count sheet and the shelf label both work.
    func lookup() {
        let code = skuText.trimmingCharacters(in: .whitespacesAndNewlines)
        saved = nil
        product = nil
        guard !code.isEmpty else { return }
        var found: Product?
        do {
            found = try products.product(sku: code)
            if found == nil, case let .product(scanned) = try products.lookup(scannedCode: code) {
                found = scanned
            }
        } catch {
            self.error = .failed
            return
        }
        guard let found else {
            error = .productNotFound
            return
        }
        guard found.tracksStock else {
            error = .untracked
            return
        }
        product = found
        error = nil
    }

    @discardableResult
    func save() -> Bool {
        guard let product else {
            error = .productNotFound
            return false
        }
        guard let quantity = DecimalInput.parse(quantityText), quantity > 0 else {
            error = .quantityInvalid
            return false
        }
        let delta = kind == .waste ? -quantity : quantity
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try stock.adjust(
                sku: product.sku, delta: delta, reason: kind.reason, occurredAt: now(),
                note: trimmed.isEmpty ? nil : trimmed
            )
        } catch {
            self.error = .failed
            return false
        }
        saved = Saved(sku: product.sku, delta: delta, stockOnHand: product.stockOnHand)
        quantityText = ""
        note = ""
        error = nil
        return true
    }

    func clearError() {
        error = nil
    }
}
