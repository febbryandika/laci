import Foundation
@testable import Laci
import LaciCore
import LaciMoney
import LaciPrint
import SwiftData
import Testing

private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor
@Suite("Receipt factory")
struct ReceiptFactoryTests {
    let dependencies: Dependencies

    init() throws {
        dependencies = try Dependencies.inMemory()
        try dependencies.products.create(Product(
            sku: "A", name: "Gula Pasir", unit: "kg", cost: 0, price: 18000, tracksStock: false, updatedAt: fixedNow
        ))
        try dependencies.products.create(Product(
            sku: "B", name: "Indomie", unit: "bungkus", cost: 0, price: 3500, tracksStock: false, updatedAt: fixedNow
        ))
    }

    func commit(_ payment: SaleDraft.Payment? = nil, saleDiscount: Discount = .none) throws -> Sale {
        let lines = [
            SaleDraft.Line(
                cart: CartLine(sku: "A", name: "Gula Pasir", quantity: 2, unitPrice: Money(18000),
                               discount: .amount(Money(1000)), taxable: true),
                listPrice: Money(18000)
            ),
            SaleDraft.Line(
                cart: CartLine(sku: "B", name: "Indomie", quantity: 3, unitPrice: Money(3500), discount: .none,
                               taxable: true),
                listPrice: Money(3500)
            ),
        ]
        let totals = Pricing.totals(lines: lines.map(\.cart), saleDiscount: saleDiscount, tax: .nonPKP)
        let settlement = try #require(Tender.settle(total: totals.grandTotal, tendered: Money(100_000)))
        let draft = SaleDraft(
            lines: lines, totals: totals, payment: payment ?? .cash(settlement), occurredAt: fixedNow
        )
        return try dependencies.sales.commit(
            draft, tradingDay: ShopDefaults.tradingDay, timeZone: ShopDefaults.timeZone
        )
    }

    @Test("Names, quantities, prices and line discounts come from the stored lines; units from the catalogue")
    func linesAndUnits() throws {
        let sale = try commit()
        let receipt = ReceiptFactory.make(sale, products: dependencies.products, isReprint: false)
        #expect(receipt.lines.map(\.name) == ["Gula Pasir", "Indomie"])
        #expect(receipt.lines.map(\.unit) == ["kg", "bungkus"])
        #expect(receipt.lines.map(\.quantity) == [2, 3])
        #expect(receipt.lines.map(\.unitPrice) == [Money(18000), Money(3500)])
        #expect(receipt.lines.map(\.discount) == [Money(1000), .zero])
        #expect(receipt.number == sale.number)
        #expect(receipt.occurredAt == fixedNow)
        #expect(receipt.timeZone == ShopDefaults.timeZone)
        #expect(receipt.shopName == ShopDefaults.shopName)
        #expect(receipt.footerLines == ShopDefaults.footerLines)
        #expect(receipt.taxRate == nil)
        #expect(receipt.logo == nil)
        #expect(receipt.isReprint == false)
    }

    @Test("A product deleted since the sale still prints, with an empty unit")
    func missingProduct() throws {
        let sale = try commit()
        let found = try dependencies.products.product(sku: "A")
        let product = try #require(found)
        try dependencies.transactor.perform { dependencies.transactor.context.delete(product) }
        let receipt = ReceiptFactory.make(sale, products: dependencies.products, isReprint: true)
        #expect(receipt.lines.map(\.unit) == ["", "bungkus"])
        #expect(receipt.isReprint)
    }

    @Test("The whole-sale discount is the stored total minus the line discounts")
    func saleDiscountSplit() throws {
        let sale = try commit(saleDiscount: .amount(Money(2500)))
        let receipt = ReceiptFactory.make(sale, products: dependencies.products, isReprint: false)
        #expect(sale.discountTotal == 3500)
        #expect(receipt.saleDiscount == Money(2500))
        #expect(receipt.subtotal == Money(sale.subtotal))
        #expect(receipt.total == Money(sale.total))
        #expect(receipt.roundingDelta == Money(sale.roundingDelta))
    }

    @Test("Cash carries tendered and change; QRIS and transfer carry the reference")
    func tenders() throws {
        let cash = try ReceiptFactory.make(commit(), products: dependencies.products, isReprint: false)
        #expect(cash.tender == .cash(tendered: Money(100_000), change: Money(100_000) - Money(45500)))

        let qris = try ReceiptFactory.make(
            commit(.qris(reference: "QR-1")), products: dependencies.products, isReprint: false
        )
        #expect(qris.tender == .qris(reference: "QR-1"))
        #expect(qris.roundingDelta == .zero)

        let transfer = try ReceiptFactory.make(
            commit(.transfer(reference: "BCA 9")), products: dependencies.products, isReprint: false
        )
        #expect(transfer.tender == .transfer(reference: "BCA 9"))
    }

    @Test("A refund prints its negated amounts as stored")
    func refund() throws {
        let original = try commit()
        let refund = try dependencies.sales.refund(
            saleID: original.id, occurredAt: fixedNow, tradingDay: ShopDefaults.tradingDay,
            timeZone: ShopDefaults.timeZone
        )
        let receipt = ReceiptFactory.make(refund, products: dependencies.products, isReprint: false)
        #expect(receipt.total == Money(-45500))
        #expect(receipt.lines.map(\.quantity) == [-2, -3])
    }
}
