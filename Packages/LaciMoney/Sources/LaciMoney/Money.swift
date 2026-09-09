import Foundation

/// Indonesian Rupiah. `Decimal` because binary floating point cannot represent 0.1, and a POS that
/// is wrong by Rp 0.0000001 per line is wrong by real money by Friday.
public struct Money: Hashable, Sendable, Comparable, AdditiveArithmetic {
    public let amount: Decimal

    public init(_ amount: Decimal) {
        self.amount = amount
    }

    public static let zero = Money(0)

    public static func + (lhs: Money, rhs: Money) -> Money {
        Money(lhs.amount + rhs.amount)
    }

    public static func - (lhs: Money, rhs: Money) -> Money {
        Money(lhs.amount - rhs.amount)
    }

    public static func < (lhs: Money, rhs: Money) -> Bool {
        lhs.amount < rhs.amount
    }

    public func times(_ quantity: Decimal) -> Money {
        Money(amount * quantity)
    }
}

/// One thing or the other. Two optional fields would permit a state ("both set") the business does
/// not have, and every screen downstream would then need a rule for it.
public enum Discount: Hashable, Sendable {
    case none
    case amount(Money)
    case percent(Decimal) // 0...100

    public func applied(to gross: Money) -> Money {
        switch self {
        case .none: .zero
        case let .amount(money): min(money, gross)
        case let .percent(percent):
            Money(Rounding.bankers(gross.amount * max(0, min(100, percent)) / 100, scale: 2))
        }
    }
}

public struct CartLine: Hashable, Sendable {
    public let sku: String, name: String
    public let quantity: Decimal
    public let unitPrice: Money
    public let discount: Discount
    public let taxable: Bool

    public init(
        sku: String,
        name: String,
        quantity: Decimal,
        unitPrice: Money,
        discount: Discount,
        taxable: Bool
    ) {
        self.sku = sku
        self.name = name
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.discount = discount
        self.taxable = taxable
    }
}

public struct LineTotal: Hashable, Sendable {
    public let gross: Money // quantity × unitPrice
    public let discount: Money
    public let net: Money // gross − discount

    public init(gross: Money, discount: Money, net: Money) {
        self.gross = gross
        self.discount = discount
        self.net = net
    }
}

public struct SaleTotals: Hashable, Sendable {
    public let subtotal: Money // Σ line net, tax-exclusive
    public let lineDiscounts: Money
    public let saleDiscount: Money
    public let taxable: Money
    public let tax: Money
    public let grandTotal: Money // exact, before cash rounding

    public init(
        subtotal: Money,
        lineDiscounts: Money,
        saleDiscount: Money,
        taxable: Money,
        tax: Money,
        grandTotal: Money
    ) {
        self.subtotal = subtotal
        self.lineDiscounts = lineDiscounts
        self.saleDiscount = saleDiscount
        self.taxable = taxable
        self.tax = tax
        self.grandTotal = grandTotal
    }
}

public struct TaxPolicy: Hashable, Sendable {
    public enum Mode: Hashable, Sendable { case none, inclusive, exclusive }

    public let mode: Mode
    public let rate: Decimal // 0.11 effective on general goods
    public static let nonPKP = TaxPolicy(mode: .none, rate: 0)

    public init(mode: Mode, rate: Decimal) {
        self.mode = mode
        self.rate = rate
    }
}
