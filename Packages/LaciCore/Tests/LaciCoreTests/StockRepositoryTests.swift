import Foundation
import LaciCore
import SwiftData
import Testing

@MainActor
@Suite("Stock repository")
struct StockRepositoryTests {
    let store: TestStore
    let products: SwiftDataProductRepository
    let stock: SwiftDataStockRepository
    let epoch = Date(timeIntervalSince1970: 0)

    init() throws {
        store = try TestStore()
        let transactor = Transactor(container: store.container)
        products = SwiftDataProductRepository(transactor: transactor)
        stock = SwiftDataStockRepository(transactor: transactor)
    }

    @Test("An adjustment moves stock on hand and records one movement with the raw reason")
    func adjust() throws {
        try products.create(makeProduct("A", stockOnHand: 10))
        try stock.adjust(sku: "A", delta: dec("-2.5"), reason: .waste, occurredAt: epoch)

        #expect(try products.product(sku: "A")?.stockOnHand == dec("7.5"))
        let movements = try stock.movements(for: "A", limit: 10)
        #expect(movements.count == 1)
        #expect(movements.first?.reasonRaw == "waste")
        #expect(try movements.first?.delta == dec("-2.5"))
        #expect(movements.first?.saleID == nil)
    }

    @Test("A batch with one missing SKU applies nothing")
    func batchIsAtomic() throws {
        try products.create(makeProduct("A", stockOnHand: 10))
        try products.create(makeProduct("B", stockOnHand: 10))
        let batch = [
            StockAdjustment(sku: "A", delta: 1), StockAdjustment(sku: "B", delta: 2),
            StockAdjustment(sku: "ZZ", delta: 3),
        ]

        #expect(throws: CoreError.productNotFound(sku: "ZZ")) {
            try stock.applyBatch(batch, reason: .stocktake, occurredAt: epoch)
        }

        let fresh = ModelContext(store.container)
        let fetched = try fresh.fetch(FetchDescriptor<Product>(sortBy: [SortDescriptor(\.sku)]))
        #expect(fetched.map(\.stockOnHand) == [10, 10])
        #expect(try fresh.fetchCount(FetchDescriptor<StockMovement>()) == 0)
    }

    @Test("Movements list newest first and honour the limit")
    func movementsOrder() throws {
        try products.create(makeProduct("A", stockOnHand: 10))
        for offset in 0 ..< 3 {
            try stock.adjust(sku: "A", delta: Decimal(offset), reason: .stockIn,
                             occurredAt: epoch.addingTimeInterval(Double(offset)))
        }
        let movements = try stock.movements(for: "A", limit: 2)
        #expect(movements.map(\.delta) == [2, 1])
    }

    @Test("A manual adjustment keeps the operator's note; a batch never has one")
    func adjustStoresNote() throws {
        try products.create(makeProduct("A", stockOnHand: 10))
        try stock.adjust(sku: "A", delta: 5, reason: .stockIn, occurredAt: epoch, note: "Kiriman supplier")
        try stock.applyBatch([StockAdjustment(sku: "A", delta: -1)], reason: .stocktake,
                             occurredAt: epoch.addingTimeInterval(1))

        let movements = try stock.movements(for: "A", limit: 10)
        #expect(movements.map(\.note) == [nil, "Kiriman supplier"])
    }

    @Test("A stocktake batch touches only the SKUs it names; an uncounted SKU is not zeroed")
    func stocktakeBatchLeavesUnscannedUntouched() throws {
        try products.create(makeProduct("A", stockOnHand: 10))
        try products.create(makeProduct("B", stockOnHand: 5))
        try products.create(makeProduct("C", stockOnHand: 8))

        try stock.applyBatch(
            [StockAdjustment(sku: "A", delta: -3), StockAdjustment(sku: "B", delta: 2)],
            reason: .stocktake, occurredAt: epoch
        )

        #expect(try products.product(sku: "A")?.stockOnHand == 7)
        #expect(try products.product(sku: "B")?.stockOnHand == 7)
        #expect(try products.product(sku: "C")?.stockOnHand == 8)
        #expect(try stock.movements(for: "C", limit: 10).isEmpty)
        let recorded = try stock.movements(for: "A", limit: 10) + stock.movements(for: "B", limit: 10)
        #expect(recorded.map(\.reasonRaw) == ["stocktake", "stocktake"])
        #expect(recorded.allSatisfy { $0.saleID == nil && $0.note == nil })
    }

    @Test("A movement range is half-open: the start instant is in, the end instant is out")
    func movementsRangeIsHalfOpen() throws {
        try products.create(makeProduct("B", stockOnHand: 10))
        try products.create(makeProduct("A", stockOnHand: 10))
        let start = epoch.addingTimeInterval(100)
        let end = epoch.addingTimeInterval(200)
        try stock.adjust(sku: "A", delta: 1, reason: .stockIn, occurredAt: epoch.addingTimeInterval(99))
        try stock.adjust(sku: "B", delta: 2, reason: .stockIn, occurredAt: start)
        try stock.adjust(sku: "A", delta: 3, reason: .stockIn, occurredAt: start)
        try stock.adjust(sku: "A", delta: 4, reason: .waste, occurredAt: epoch.addingTimeInterval(150))
        try stock.adjust(sku: "A", delta: 5, reason: .stockIn, occurredAt: end)

        let found = try stock.movements(from: start, before: end)
        #expect(found.map(\.delta) == [3, 2, 4])
        #expect(found.map(\.productSKU) == ["A", "B", "A"])
    }
}
