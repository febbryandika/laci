import Foundation
import SwiftData

/// Single-row lookups shared by the repositories. Internal: callers outside the package go through
/// a repository protocol.
extension ModelContext {
    func product(sku: String) throws -> Product? {
        var descriptor = FetchDescriptor<Product>(predicate: #Predicate { $0.sku == sku })
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    func requireProduct(sku: String) throws -> Product {
        guard let product = try product(sku: sku) else { throw CoreError.productNotFound(sku: sku) }
        return product
    }

    func barcode(value: String) throws -> Barcode? {
        var descriptor = FetchDescriptor<Barcode>(predicate: #Predicate { $0.value == value })
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    func sale(id: UUID) throws -> Sale? {
        var descriptor = FetchDescriptor<Sale>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    func requireSale(id: UUID) throws -> Sale {
        guard let sale = try sale(id: id) else { throw CoreError.saleNotFound(id: id) }
        return sale
    }

    /// The stock a sale took (or, for a refund, gave back): what a void or refund reverses.
    func saleMovements(saleID: UUID) throws -> [StockMovement] {
        let sale = MovementReason.sale.rawValue
        return try fetch(FetchDescriptor<StockMovement>(predicate: #Predicate {
            $0.saleID == saleID && $0.reasonRaw == sale
        }))
    }
}
