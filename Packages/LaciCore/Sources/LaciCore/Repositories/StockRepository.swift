import Foundation
import SwiftData

public struct StockAdjustment: Hashable, Sendable {
    public let sku: String
    public let delta: Decimal

    public init(sku: String, delta: Decimal) {
        self.sku = sku
        self.delta = delta
    }
}

@MainActor
public protocol StockRepository: AnyObject {
    /// Newest first.
    func movements(for sku: String, limit: Int) throws -> [StockMovement]
    func adjust(sku: String, delta: Decimal, reason: MovementReason, occurredAt: Date) throws
    /// Applied as one batch or not at all (SPEC §3.2).
    func applyBatch(_ adjustments: [StockAdjustment], reason: MovementReason, occurredAt: Date) throws
}

@MainActor
public final class SwiftDataStockRepository: StockRepository {
    private let transactor: Transactor
    private var context: ModelContext {
        transactor.context
    }

    public init(transactor: Transactor) {
        self.transactor = transactor
    }

    public func movements(for sku: String, limit: Int) throws -> [StockMovement] {
        var descriptor = FetchDescriptor<StockMovement>(
            predicate: #Predicate { $0.productSKU == sku },
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    public func adjust(sku: String, delta: Decimal, reason: MovementReason, occurredAt: Date) throws {
        try applyBatch([StockAdjustment(sku: sku, delta: delta)], reason: reason, occurredAt: occurredAt)
    }

    public func applyBatch(_ adjustments: [StockAdjustment], reason: MovementReason, occurredAt: Date) throws {
        try transactor.perform {
            for adjustment in adjustments {
                let product = try context.requireProduct(sku: adjustment.sku)
                product.stockOnHand += adjustment.delta
                context.insert(StockMovement(
                    productSKU: adjustment.sku, delta: adjustment.delta, reason: reason,
                    occurredAt: occurredAt, saleID: nil
                ))
            }
        }
    }
}
