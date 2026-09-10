import Foundation
import LaciMoney

/// The two paper widths these shops own. Columns are what `ESCPOSBuilder.row` measures; dots are
/// what the logo is rasterised at.
public enum PaperWidth: Hashable, Sendable {
    case mm58
    case mm80

    public var columns: Int {
        switch self {
        case .mm58: 32
        case .mm80: 48
        }
    }

    public var dots: Int {
        switch self {
        case .mm58: 384
        case .mm80: 576
        }
    }
}

/// Everything a printed struk says, already resolved: names and prices as they were at the sale,
/// never re-read from the catalogue, so a reprint in March says what it said in January.
public struct Receipt: Hashable, Sendable {
    public struct Line: Hashable, Sendable {
        public let name: String
        public let quantity: Decimal
        public let unit: String
        public let unitPrice: Money
        /// Resolved amount; percent discounts are already applied.
        public let discount: Money

        public init(name: String, quantity: Decimal, unit: String, unitPrice: Money, discount: Money) {
            self.name = name
            self.quantity = quantity
            self.unit = unit
            self.unitPrice = unitPrice
            self.discount = discount
        }
    }

    public enum Tender: Hashable, Sendable {
        case cash(tendered: Money, change: Money)
        case qris(reference: String)
        case transfer(reference: String)
    }

    public let shopName: String
    public let shopLines: [String]
    public let footerLines: [String]
    public let number: Int
    public let occurredAt: Date
    public let timeZone: TimeZone
    public let lines: [Line]
    public let subtotal: Money
    /// Whole-sale discount only; line discounts are shown per line and already inside `subtotal`.
    public let saleDiscount: Money
    public let taxTotal: Money
    /// Effective PPN rate as a fraction (0.11); nil when the shop is not PKP.
    public let taxRate: Decimal?
    /// Signed, rounded − exact (SPEC §8.3). Zero for non-cash tender.
    public let roundingDelta: Money
    public let total: Money
    public let tender: Tender
    public let isReprint: Bool
    public let logo: MonoBitmap?

    public init(
        shopName: String,
        shopLines: [String],
        footerLines: [String],
        number: Int,
        occurredAt: Date,
        timeZone: TimeZone,
        lines: [Line],
        subtotal: Money,
        saleDiscount: Money,
        taxTotal: Money,
        taxRate: Decimal?,
        roundingDelta: Money,
        total: Money,
        tender: Tender,
        isReprint: Bool,
        logo: MonoBitmap?
    ) {
        self.shopName = shopName
        self.shopLines = shopLines
        self.footerLines = footerLines
        self.number = number
        self.occurredAt = occurredAt
        self.timeZone = timeZone
        self.lines = lines
        self.subtotal = subtotal
        self.saleDiscount = saleDiscount
        self.taxTotal = taxTotal
        self.taxRate = taxRate
        self.roundingDelta = roundingDelta
        self.total = total
        self.tender = tender
        self.isReprint = isReprint
        self.logo = logo
    }
}
