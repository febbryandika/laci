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
    /// One manual movement; `note` is the operator's reason and is stored verbatim.
    func adjust(sku: String, delta: Decimal, reason: MovementReason, occurredAt: Date, note: String?) throws
    /// Applied as one batch or not at all (SPEC §3.2). Batch movements carry no note.
    func applyBatch(_ adjustments: [StockAdjustment], reason: MovementReason, occurredAt: Date) throws
}

public extension StockRepository {
    func adjust(sku: String, delta: Decimal, reason: MovementReason, occurredAt: Date) throws {
        try adjust(sku: sku, delta: delta, reason: reason, occurredAt: occurredAt, note: nil)
    }
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

    public func adjust(
        sku: String, delta: Decimal, reason: MovementReason, occurredAt: Date, note: String?
    ) throws {
        try transactor.perform {
            try move(StockAdjustment(sku: sku, delta: delta), reason: reason, occurredAt: occurredAt, note: note)
        }
    }

    public func applyBatch(_ adjustments: [StockAdjustment], reason: MovementReason, occurredAt: Date) throws {
        try transactor.perform {
            for adjustment in adjustments {
                try move(adjustment, reason: reason, occurredAt: occurredAt, note: nil)
            }
        }
    }

    /// Inside `transactor.perform` only.
    private func move(_ adjustment: StockAdjustment, reason: MovementReason, occurredAt: Date, note: String?) throws {
        let product = try context.requireProduct(sku: adjustment.sku)
        product.stockOnHand += adjustment.delta
        context.insert(StockMovement(
            productSKU: adjustment.sku, delta: adjustment.delta, reason: reason,
            occurredAt: occurredAt, saleID: nil, note: note
        ))
    }
}
