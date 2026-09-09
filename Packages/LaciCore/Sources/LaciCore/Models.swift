import Foundation
import SwiftData

/// Schema V1 is what ships to TestFlight (SPEC §4). Every later change gets a new `VersionedSchema`
/// and a `MigrationStage`; until then V1 is edited in place. `Payout` and `CloseOut.cashRefunds` were
/// added in Phase 6 for SPEC §3.3.4 and §8.4.
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        [Product.self, Barcode.self, Sale.self, SaleLine.self, StockMovement.self, CloseOut.self, Payout.self]
    }

    @Model public final class Product {
        @Attribute(.unique) public var sku: String
        public var name: String
        public var unit: String // "pcs", "kg", "bungkus"
        public var cost: Decimal
        public var price: Decimal
        public var tracksStock: Bool
        public var stockOnHand: Decimal // Decimal, not Int: 0.5 kg is a real sale
        public var isArchived: Bool
        public var updatedAt: Date
        @Relationship(deleteRule: .cascade, inverse: \Barcode.product) public var barcodes: [Barcode]

        public init(
            sku: String, name: String, unit: String, cost: Decimal, price: Decimal, tracksStock: Bool,
            stockOnHand: Decimal = 0, isArchived: Bool = false, updatedAt: Date
        ) {
            self.sku = sku
            self.name = name
            self.unit = unit
            self.cost = cost
            self.price = price
            self.tracksStock = tracksStock
            self.stockOnHand = stockOnHand
            self.isArchived = isArchived
            self.updatedAt = updatedAt
            barcodes = []
        }
    }

    @Model public final class Barcode {
        @Attribute(.unique) public var value: String // EAN-13, EAN-8, CODE-128 payload
        public var symbology: String
        public var product: Product?

        public init(value: String, symbology: Symbology) {
            self.value = value
            self.symbology = symbology.rawValue
            product = nil
        }
    }

    @Model public final class Sale {
        @Attribute(.unique) public internal(set) var id: UUID
        public internal(set) var number: Int // human-facing, monotonic, per install
        public internal(set) var occurredAt: Date
        public internal(set) var tradingDay: Date // start-of-day in the shop's timezone; the join key
        public internal(set) var subtotal: Decimal
        public internal(set) var discountTotal: Decimal
        public internal(set) var taxTotal: Decimal
        public internal(set) var roundingDelta: Decimal // §8.3, signed
        public internal(set) var total: Decimal // what the customer actually pays
        public internal(set) var paymentMethodRaw: String // "cash" | "qris" | "transfer"
        public internal(set) var amountTendered: Decimal?
        public internal(set) var changeGiven: Decimal?
        public internal(set) var reference: String?
        public internal(set) var voidedAt: Date?
        public internal(set) var voidReason: String?
        public internal(set) var refundsSaleID: UUID?
        @Relationship(deleteRule: .cascade, inverse: \SaleLine.sale) public internal(set) var lines: [SaleLine]

        public init(
            id: UUID, number: Int, occurredAt: Date, tradingDay: Date, subtotal: Decimal,
            discountTotal: Decimal, taxTotal: Decimal, roundingDelta: Decimal, total: Decimal,
            paymentMethod: PaymentMethod, amountTendered: Decimal?, changeGiven: Decimal?, reference: String?
        ) {
            self.id = id
            self.number = number
            self.occurredAt = occurredAt
            self.tradingDay = tradingDay
            self.subtotal = subtotal
            self.discountTotal = discountTotal
            self.taxTotal = taxTotal
            self.roundingDelta = roundingDelta
            self.total = total
            paymentMethodRaw = paymentMethod.rawValue
            self.amountTendered = amountTendered
            self.changeGiven = changeGiven
            self.reference = reference
            voidedAt = nil
            voidReason = nil
            refundsSaleID = nil
            lines = []
        }
    }

    @Model public final class SaleLine {
        public internal(set) var productSKU: String // denormalised on purpose: a reprint must say what it said
        public internal(set) var name: String
        public internal(set) var quantity: Decimal
        public internal(set) var unitPrice: Decimal
        public internal(set) var listPrice: Decimal
        public internal(set) var discountAmount: Decimal // percent is resolved to an amount at commit
        public internal(set) var lineTotal: Decimal
        public internal(set) var sale: Sale?

        public init(
            productSKU: String, name: String, quantity: Decimal, unitPrice: Decimal, listPrice: Decimal,
            discountAmount: Decimal, lineTotal: Decimal
        ) {
            self.productSKU = productSKU
            self.name = name
            self.quantity = quantity
            self.unitPrice = unitPrice
            self.listPrice = listPrice
            self.discountAmount = discountAmount
            self.lineTotal = lineTotal
            sale = nil
        }
    }

    @Model public final class StockMovement {
        public var productSKU: String
        public var delta: Decimal
        public var reasonRaw: String // "sale" | "void" | "stock_in" | "stocktake" | "waste"
        public var occurredAt: Date
        public var saleID: UUID?

        public init(productSKU: String, delta: Decimal, reason: MovementReason, occurredAt: Date, saleID: UUID?) {
            self.productSKU = productSKU
            self.delta = delta
            reasonRaw = reason.rawValue
            self.occurredAt = occurredAt
            self.saleID = saleID
        }
    }

    @Model public final class CloseOut {
        @Attribute(.unique) public var tradingDay: Date
        public var openingFloat: Decimal
        public var cashSales: Decimal
        public var cashRefunds: Decimal = 0 // DrawerInputs.cashRefunds; a default so V1 rows stay readable
        public var payouts: Decimal // Σ payouts that went into reconcile, not the closing setoran
        public var expectedDrawer: Decimal
        public var countedDrawer: Decimal
        public var discrepancy: Decimal // counted − expected; stored, never recomputed
        public var note: String?
        public var closedAt: Date
        public var attribution: String? // §10: "operator" | "bug" | "unresolved"

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
    }

    /// Cash that left the drawer other than as change (SPEC §3.3.4, §8.4): a supplier paid from the
    /// till, petty cash, or a setoran. The closing setoran is one of these, dated `CloseOut.closedAt`.
    @Model public final class Payout {
        public var tradingDay: Date
        public var kindRaw: String // "supplier" | "petty_cash" | "setoran"
        public var amount: Decimal
        public var note: String
        public var occurredAt: Date

        public init(tradingDay: Date, kind: PayoutKind, amount: Decimal, note: String, occurredAt: Date) {
            self.tradingDay = tradingDay
            kindRaw = kind.rawValue
            self.amount = amount
            self.note = note
            self.occurredAt = occurredAt
        }
    }
}

public typealias Product = SchemaV1.Product
public typealias Barcode = SchemaV1.Barcode
public typealias Sale = SchemaV1.Sale
public typealias SaleLine = SchemaV1.SaleLine
public typealias StockMovement = SchemaV1.StockMovement
public typealias CloseOut = SchemaV1.CloseOut
public typealias Payout = SchemaV1.Payout
