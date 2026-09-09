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
}
