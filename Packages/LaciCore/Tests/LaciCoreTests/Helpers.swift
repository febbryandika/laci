import Foundation
import LaciCore
import LaciMoney
import SwiftData
import Testing

/// `Decimal` float literals are not exact (`1.11` is 1.1100000000000002048), so every non-integer
/// value in these tests is built from a string.
func dec(_ text: String) throws -> Decimal {
    try #require(Decimal(string: text))
}

func money(_ text: String) throws -> Money {
    try Money(dec(text))
}

/// One in-memory container per test. The configuration name is unique so parallel suites never
/// share a store.
@MainActor
struct TestStore {
    let container: ModelContainer

    init() throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(
            UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
        )
        container = try ModelContainer(for: schema, configurations: [configuration])
    }
}

/// A product with sensible defaults; tests override only what they assert on.
func makeProduct(
    _ sku: String, name: String? = nil, tracksStock: Bool = true, stockOnHand: Decimal = 0,
    cost: Decimal = 1000, price: Decimal = 1500
) -> Product {
    Product(
        sku: sku, name: name ?? "Item \(sku)", unit: "pcs", cost: cost, price: price,
        tracksStock: tracksStock, stockOnHand: stockOnHand, updatedAt: Date(timeIntervalSince1970: 0)
    )
}

let jakarta = TimeZone(identifier: "Asia/Jakarta")!

/// A wall-clock instant in the shop's zone (WIB), never the device zone.
func wib(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = jakarta
    let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    return try #require(calendar.date(from: components))
}

/// Draft builders shared by the sale suites; a cash draft settles at the rounded total.
func line(
    _ sku: String, qty: Decimal = 1, price: Decimal = 5000, list: Decimal? = nil, discount: Discount = .none
) -> SaleDraft.Line {
    let cart = CartLine(
        sku: sku, name: "Item \(sku)", quantity: qty, unitPrice: Money(price), discount: discount, taxable: true
    )
    return SaleDraft.Line(cart: cart, listPrice: Money(list ?? price))
}

func totals(_ lines: [SaleDraft.Line]) -> SaleTotals {
    Pricing.totals(lines: lines.map(\.cart), saleDiscount: .none, tax: .nonPKP)
}

func cashDraft(
    _ lines: [SaleDraft.Line], tendered: Decimal = 100_000, occurredAt: Date? = nil
) throws -> SaleDraft {
    let totals = totals(lines)
    let settlement = try #require(Tender.settle(total: totals.grandTotal, tendered: Money(tendered)))
    return try SaleDraft(lines: lines, totals: totals, payment: .cash(settlement),
                         occurredAt: occurredAt ?? wib(2026, 9, 10, 12))
}
