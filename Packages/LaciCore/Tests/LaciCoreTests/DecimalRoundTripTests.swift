import Foundation
import LaciCore
import SwiftData
import Testing

@MainActor
@Suite("Decimal round-trip through SwiftData")
struct DecimalRoundTripTests {
    let store: TestStore

    init() throws {
        store = try TestStore()
    }

    @Test("A persisted Decimal refetches losslessly", arguments: ["0.5", "149000", "12350.55", "-1500", "0.3"])
    func costSurvives(text: String) throws {
        let value = text == "0.3" ? try dec("0.1") + dec("0.2") : try dec(text)
        let product = Product(
            sku: "SKU-\(text)", name: "Item", unit: "pcs", cost: value, price: 0,
            tracksStock: true, updatedAt: Date(timeIntervalSince1970: 0)
        )
        store.container.mainContext.insert(product)
        try store.container.mainContext.save()

        // A fresh context rematerialises the row from the store instead of returning the cached object.
        let fresh = ModelContext(store.container)
        let fetched = try #require(try fresh.fetch(FetchDescriptor<Product>()).first)
        #expect(fetched.cost == value)
        #expect(text == "\(fetched.cost)")
    }

    @Test("Half a kilogram of stock on hand survives the round-trip")
    func fractionalStockSurvives() throws {
        let product = try Product(
            sku: "BERAS", name: "Beras", unit: "kg", cost: 12000, price: 14000,
            tracksStock: true, stockOnHand: dec("0.5"), updatedAt: Date(timeIntervalSince1970: 0)
        )
        store.container.mainContext.insert(product)
        try store.container.mainContext.save()

        let fresh = ModelContext(store.container)
        let fetched = try #require(try fresh.fetch(FetchDescriptor<Product>()).first)
        #expect(try fetched.stockOnHand == dec("0.5"))
    }
}
