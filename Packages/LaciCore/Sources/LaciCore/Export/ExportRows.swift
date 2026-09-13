import Foundation

/// Plain values for the four exports (SPEC §5.2), copied off the models on the main context so
/// the codec never touches SwiftData. Column order is fixed by `ExportCSV`.
public struct SaleExportRow: Hashable, Sendable {
    public let number: Int
    public let id: UUID
    public let occurredAt: Date
    public let tradingDay: Date
    public let subtotal: Decimal
    public let discountTotal: Decimal
    public let taxTotal: Decimal
    public let roundingDelta: Decimal
    public let total: Decimal
    public let paymentMethod: String
    public let amountTendered: Decimal?
    public let changeGiven: Decimal?
    public let reference: String?
    public let voidedAt: Date?
    public let voidReason: String?
    public let refundsSaleID: UUID?
    public let receiptFailedAt: Date?

    public init(
        number: Int, id: UUID, occurredAt: Date, tradingDay: Date, subtotal: Decimal, discountTotal: Decimal,
        taxTotal: Decimal, roundingDelta: Decimal, total: Decimal, paymentMethod: String,
        amountTendered: Decimal?, changeGiven: Decimal?, reference: String?, voidedAt: Date?, voidReason: String?,
        refundsSaleID: UUID?, receiptFailedAt: Date?
    ) {
        self.number = number
        self.id = id
        self.occurredAt = occurredAt
        self.tradingDay = tradingDay
        self.subtotal = subtotal
        self.discountTotal = discountTotal
        self.taxTotal = taxTotal
        self.roundingDelta = roundingDelta
        self.total = total
        self.paymentMethod = paymentMethod
        self.amountTendered = amountTendered
        self.changeGiven = changeGiven
        self.reference = reference
        self.voidedAt = voidedAt
        self.voidReason = voidReason
        self.refundsSaleID = refundsSaleID
        self.receiptFailedAt = receiptFailedAt
    }

    @MainActor
    public init(_ sale: Sale) {
        self.init(
            number: sale.number, id: sale.id, occurredAt: sale.occurredAt, tradingDay: sale.tradingDay,
            subtotal: sale.subtotal, discountTotal: sale.discountTotal, taxTotal: sale.taxTotal,
            roundingDelta: sale.roundingDelta, total: sale.total, paymentMethod: sale.paymentMethodRaw,
            amountTendered: sale.amountTendered, changeGiven: sale.changeGiven, reference: sale.reference,
            voidedAt: sale.voidedAt, voidReason: sale.voidReason, refundsSaleID: sale.refundsSaleID,
            receiptFailedAt: sale.receiptFailedAt
        )
    }
}

public struct SaleLineExportRow: Hashable, Sendable {
    public let saleNumber: Int
    public let saleID: UUID
    public let productSKU: String
    public let name: String
    public let quantity: Decimal
    public let unitPrice: Decimal
    public let listPrice: Decimal
    public let discountAmount: Decimal
    public let lineTotal: Decimal

    public init(
        saleNumber: Int, saleID: UUID, productSKU: String, name: String, quantity: Decimal, unitPrice: Decimal,
        listPrice: Decimal, discountAmount: Decimal, lineTotal: Decimal
    ) {
        self.saleNumber = saleNumber
        self.saleID = saleID
        self.productSKU = productSKU
        self.name = name
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.listPrice = listPrice
        self.discountAmount = discountAmount
        self.lineTotal = lineTotal
    }

    /// A sale holds one line per SKU, and a relationship array has no stable order, so the lines
    /// are sorted by SKU rather than numbered.
    @MainActor
    public static func rows(of sale: Sale) -> [SaleLineExportRow] {
        sale.lines.sorted { $0.productSKU < $1.productSKU }.map { line in
            SaleLineExportRow(
                saleNumber: sale.number, saleID: sale.id, productSKU: line.productSKU, name: line.name,
                quantity: line.quantity, unitPrice: line.unitPrice, listPrice: line.listPrice,
                discountAmount: line.discountAmount, lineTotal: line.lineTotal
            )
        }
    }
}

public struct StockMovementExportRow: Hashable, Sendable {
    public let occurredAt: Date
    public let productSKU: String
    public let delta: Decimal
    public let reason: String
    public let saleID: UUID?
    public let note: String?

    public init(occurredAt: Date, productSKU: String, delta: Decimal, reason: String, saleID: UUID?, note: String?) {
        self.occurredAt = occurredAt
        self.productSKU = productSKU
        self.delta = delta
        self.reason = reason
        self.saleID = saleID
        self.note = note
    }

    @MainActor
    public init(_ movement: StockMovement) {
        self.init(
            occurredAt: movement.occurredAt, productSKU: movement.productSKU, delta: movement.delta,
            reason: movement.reasonRaw, saleID: movement.saleID, note: movement.note
        )
    }
}

public struct CloseOutExportRow: Hashable, Sendable {
    public let tradingDay: Date
    public let openingFloat: Decimal
    public let cashSales: Decimal
    public let cashRefunds: Decimal
    public let payouts: Decimal
    public let expectedDrawer: Decimal
    public let countedDrawer: Decimal
    public let discrepancy: Decimal
    public let note: String?
    public let closedAt: Date
    public let attribution: String?

    public init(
        tradingDay: Date, openingFloat: Decimal, cashSales: Decimal, cashRefunds: Decimal, payouts: Decimal,
        expectedDrawer: Decimal, countedDrawer: Decimal, discrepancy: Decimal, note: String?, closedAt: Date,
        attribution: String?
    ) {
        self.tradingDay = tradingDay
        self.openingFloat = openingFloat
        self.cashSales = cashSales
        self.cashRefunds = cashRefunds
        self.payouts = payouts
        self.expectedDrawer = expectedDrawer
        self.countedDrawer = countedDrawer
        self.discrepancy = discrepancy
        self.note = note
        self.closedAt = closedAt
        self.attribution = attribution
    }

    @MainActor
    public init(_ closeOut: CloseOut) {
        self.init(
            tradingDay: closeOut.tradingDay, openingFloat: closeOut.openingFloat, cashSales: closeOut.cashSales,
            cashRefunds: closeOut.cashRefunds, payouts: closeOut.payouts, expectedDrawer: closeOut.expectedDrawer,
            countedDrawer: closeOut.countedDrawer, discrepancy: closeOut.discrepancy, note: closeOut.note,
            closedAt: closeOut.closedAt, attribution: closeOut.attribution
        )
    }
}
