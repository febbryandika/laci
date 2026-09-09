import Foundation
import LaciMoney
import SwiftData

/// Everything the sell screen knows at checkout, in the money engine's own types. The repository
/// collapses `Money` to `Decimal` and a percent discount to an amount at the persistence edge.
public struct SaleDraft: Hashable, Sendable {
    public struct Line: Hashable, Sendable {
        public let cart: CartLine
        /// Retained for reporting when `cart.unitPrice` is an override (SPEC §3.1.4).
        public let listPrice: Money

        public init(cart: CartLine, listPrice: Money) {
            self.cart = cart
            self.listPrice = listPrice
        }
    }

    public enum Payment: Hashable, Sendable {
        case cash(CashSettlement)
        case qris(reference: String)
        case transfer(reference: String)
    }

    public let lines: [Line]
    public let totals: SaleTotals
    public let payment: Payment
    public let occurredAt: Date

    public init(lines: [Line], totals: SaleTotals, payment: Payment, occurredAt: Date) {
        self.lines = lines
        self.totals = totals
        self.payment = payment
        self.occurredAt = occurredAt
    }
}

@MainActor
public protocol SaleRepository: AnyObject {
    func nextNumber() throws -> Int
    /// Sale insert, line inserts and stock decrements in one transaction (SPEC §3.1.7). The trading
    /// day is bucketed here, once, and stored.
    func commit(_ draft: SaleDraft, tradingDay: TradingDay, timeZone: TimeZone) throws -> Sale
    func sale(id: UUID) throws -> Sale?
    func sale(number: Int) throws -> Sale?
    /// By sale number.
    func sales(on tradingDay: Date, limit: Int) throws -> [Sale]
    /// Newest first, keyset-paged: the sales numbered below `number`, or the newest when nil.
    func recent(before number: Int?, limit: Int) throws -> [Sale]
    /// The non-voided refunds of a sale, by number.
    func refunds(of saleID: UUID) throws -> [Sale]
    /// Marks the sale and reverses its stock movements with reason `void` in one transaction
    /// (SPEC §3.1.6). Nothing is deleted; the void fields are the only mutation a committed sale
    /// ever receives.
    func void(saleID: UUID, reason: String, occurredAt: Date) throws
    /// A new sale linked through `refundsSaleID` with every line and total negated, restoring the
    /// original's stock in the same transaction. Whole sale only.
    func refund(saleID: UUID, occurredAt: Date, tradingDay: TradingDay, timeZone: TimeZone) throws -> Sale
}

@MainActor
public final class SwiftDataSaleRepository: SaleRepository {
    private let transactor: Transactor
    private var context: ModelContext {
        transactor.context
    }

    public init(transactor: Transactor) {
        self.transactor = transactor
    }

    public func nextNumber() throws -> Int {
        var descriptor = FetchDescriptor<Sale>(sortBy: [SortDescriptor(\.number, order: .reverse)])
        descriptor.fetchLimit = 1
        return try (context.fetch(descriptor).first?.number ?? 0) + 1
    }

    public func commit(_ draft: SaleDraft, tradingDay: TradingDay, timeZone: TimeZone) throws -> Sale {
        try transactor.perform {
            guard !draft.lines.isEmpty else { throw CoreError.emptySale }
            let day = tradingDay.bucket(for: draft.occurredAt, timeZone: timeZone)
            let sale = try Self.makeSale(draft, number: nextNumber(), tradingDay: day)
            context.insert(sale)
            for line in draft.lines {
                let product = try context.requireProduct(sku: line.cart.sku)
                let stored = Self.makeLine(line)
                context.insert(stored)
                stored.sale = sale
                if product.tracksStock {
                    decrement(product, by: line.cart.quantity, saleID: sale.id, at: draft.occurredAt)
                }
            }
            return sale
        }
    }

    public func sale(id: UUID) throws -> Sale? {
        var descriptor = FetchDescriptor<Sale>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func sale(number: Int) throws -> Sale? {
        var descriptor = FetchDescriptor<Sale>(predicate: #Predicate { $0.number == number })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func sales(on tradingDay: Date, limit: Int) throws -> [Sale] {
        var descriptor = FetchDescriptor<Sale>(
            predicate: #Predicate { $0.tradingDay == tradingDay }, sortBy: [SortDescriptor(\.number)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    public func recent(before number: Int?, limit: Int) throws -> [Sale] {
        var descriptor = FetchDescriptor<Sale>(sortBy: [SortDescriptor(\.number, order: .reverse)])
        if let number {
            descriptor.predicate = #Predicate { $0.number < number }
        }
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    public func refunds(of saleID: UUID) throws -> [Sale] {
        try context.fetch(FetchDescriptor<Sale>(
            predicate: #Predicate { $0.refundsSaleID == saleID && $0.voidedAt == nil },
            sortBy: [SortDescriptor(\.number)]
        ))
    }

    public func void(saleID: UUID, reason: String, occurredAt: Date) throws {
        try transactor.perform {
            let sale = try context.requireSale(id: saleID)
            guard sale.voidedAt == nil else { throw CoreError.saleAlreadyVoided(id: saleID) }
            guard try refunds(of: saleID).isEmpty else { throw CoreError.saleHasLiveRefund(id: saleID) }
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw CoreError.voidReasonRequired }
            sale.voidedAt = occurredAt
            sale.voidReason = trimmed
            try reverse(sale, reason: .void, saleID: sale.id, occurredAt: occurredAt)
        }
    }

    public func refund(saleID: UUID, occurredAt: Date, tradingDay: TradingDay, timeZone: TimeZone) throws -> Sale {
        try transactor.perform {
            let original = try context.requireSale(id: saleID)
            guard original.voidedAt == nil else { throw CoreError.saleAlreadyVoided(id: saleID) }
            guard original.refundsSaleID == nil else { throw CoreError.saleIsRefund(id: saleID) }
            guard try refunds(of: saleID).isEmpty else { throw CoreError.saleHasLiveRefund(id: saleID) }
            let refund = try Self.mirror(
                original, number: nextNumber(), occurredAt: occurredAt,
                tradingDay: tradingDay.bucket(for: occurredAt, timeZone: timeZone)
            )
            context.insert(refund)
            for line in original.lines {
                let stored = Self.mirror(line)
                context.insert(stored)
                stored.sale = refund
            }
            try reverse(original, reason: .sale, saleID: refund.id, occurredAt: occurredAt)
            return refund
        }
    }

    private static func makeSale(_ draft: SaleDraft, number: Int, tradingDay: Date) throws -> Sale {
        let totals = draft.totals
        let settled = try Settled.of(draft.payment, grandTotal: totals.grandTotal)
        return Sale(
            id: UUID(), number: number, occurredAt: draft.occurredAt, tradingDay: tradingDay,
            subtotal: totals.subtotal.amount, discountTotal: (totals.lineDiscounts + totals.saleDiscount).amount,
            taxTotal: totals.tax.amount, roundingDelta: settled.roundingDelta.amount, total: settled.total.amount,
            paymentMethod: settled.method, amountTendered: settled.tendered?.amount,
            changeGiven: settled.change?.amount, reference: settled.reference
        )
    }

    private static func makeLine(_ line: SaleDraft.Line) -> SaleLine {
        let total = Pricing.total(for: line.cart)
        return SaleLine(
            productSKU: line.cart.sku, name: line.cart.name, quantity: line.cart.quantity,
            unitPrice: line.cart.unitPrice.amount, listPrice: line.listPrice.amount,
            discountAmount: total.discount.amount, lineTotal: total.net.amount
        )
    }

    /// The refund carries the original's channel verbatim; a cash refund therefore pays out the
    /// rounded total, which is what leaves the drawer.
    private static func mirror(_ original: Sale, number: Int, occurredAt: Date, tradingDay: Date) throws -> Sale {
        let refund = Sale(
            id: UUID(), number: number, occurredAt: occurredAt, tradingDay: tradingDay,
            subtotal: -original.subtotal, discountTotal: -original.discountTotal, taxTotal: -original.taxTotal,
            roundingDelta: -original.roundingDelta, total: -original.total,
            paymentMethod: .cash, amountTendered: nil, changeGiven: nil, reference: original.reference
        )
        refund.paymentMethodRaw = original.paymentMethodRaw
        refund.refundsSaleID = original.id
        return refund
    }

    private static func mirror(_ line: SaleLine) -> SaleLine {
        SaleLine(
            productSKU: line.productSKU, name: line.name, quantity: -line.quantity, unitPrice: line.unitPrice,
            listPrice: line.listPrice, discountAmount: -line.discountAmount, lineTotal: -line.lineTotal
        )
    }

    private func decrement(_ product: Product, by quantity: Decimal, saleID: UUID, at occurredAt: Date) {
        product.stockOnHand -= quantity
        context.insert(StockMovement(
            productSKU: product.sku, delta: -quantity, reason: .sale, occurredAt: occurredAt, saleID: saleID
        ))
    }

    /// Reverses exactly the movements the sale recorded, so a product whose `tracksStock` changed
    /// since the sale still gets back precisely what was taken, once.
    private func reverse(_ sale: Sale, reason: MovementReason, saleID: UUID, occurredAt: Date) throws {
        for movement in try context.saleMovements(saleID: sale.id) {
            let product = try context.requireProduct(sku: movement.productSKU)
            product.stockOnHand -= movement.delta
            context.insert(StockMovement(
                productSKU: movement.productSKU, delta: -movement.delta, reason: reason, occurredAt: occurredAt,
                saleID: saleID
            ))
        }
    }
}

/// The tender-dependent columns of a sale (SPEC §8.3): cash rounds and carries the delta,
/// a digital channel charges the exact amount.
private struct Settled {
    let method: PaymentMethod
    let total: Money
    let roundingDelta: Money
    let tendered: Money?
    let change: Money?
    let reference: String?

    static func of(_ payment: SaleDraft.Payment, grandTotal: Money) throws -> Settled {
        switch payment {
        case let .cash(settlement):
            guard settlement.exact == grandTotal else { throw CoreError.settlementMismatch }
            return Settled(
                method: .cash, total: settlement.rounded, roundingDelta: settlement.roundingDelta,
                tendered: settlement.tendered, change: settlement.change, reference: nil
            )
        case let .qris(reference):
            return digital(.qris, total: grandTotal, reference: reference)
        case let .transfer(reference):
            return digital(.transfer, total: grandTotal, reference: reference)
        }
    }

    private static func digital(_ method: PaymentMethod, total: Money, reference: String) -> Settled {
        Settled(method: method, total: total, roundingDelta: .zero, tendered: nil, change: nil, reference: reference)
    }
}
