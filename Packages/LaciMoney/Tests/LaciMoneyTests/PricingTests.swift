import Foundation
import LaciMoney
import Testing

private func line(
    _ quantity: Decimal,
    at unitPrice: Decimal,
    discount: Discount = .none,
    taxable: Bool = true
) -> CartLine {
    CartLine(
        sku: "SKU", name: "Item", quantity: quantity,
        unitPrice: Money(unitPrice), discount: discount, taxable: taxable
    )
}

private let inclusive = TaxPolicy(mode: .inclusive, rate: 0.11)
private let exclusive = TaxPolicy(mode: .exclusive, rate: 0.11)

@Suite("Line totals")
struct LineTotalTests {
    @Test("Gross is quantity × unit price, banker's-rounded to two places")
    func gross() throws {
        #expect(Pricing.total(for: line(3, at: 2499)).gross == Money(7497))
        #expect(try Pricing.total(for: line(dec("1.5"), at: 3333)).gross == money("4999.5"))
        #expect(try Pricing.total(for: line(dec("0.333"), at: 1000)).gross == Money(333))
        #expect(try Pricing.total(for: line(dec("2.5"), at: dec("1.01"))).gross == money("2.52"))
    }

    @Test("Amount discount")
    func amountDiscount() {
        let total = Pricing.total(for: line(1, at: 10000, discount: .amount(Money(1500))))
        #expect(total == LineTotal(gross: Money(10000), discount: Money(1500), net: Money(8500)))
    }

    @Test("Amount discount larger than the line is clamped, net never negative")
    func amountDiscountClamped() {
        let total = Pricing.total(for: line(1, at: 10000, discount: .amount(Money(12000))))
        #expect(total == LineTotal(gross: Money(10000), discount: Money(10000), net: .zero))
    }

    @Test("Percent discount")
    func percentDiscount() throws {
        let total = Pricing.total(for: line(1, at: 12345, discount: .percent(15)))
        #expect(try total == LineTotal(gross: Money(12345), discount: money("1851.75"), net: money("10493.25")))
    }

    @Test("Percent discount over 100 is clamped")
    func percentDiscountClamped() {
        let total = Pricing.total(for: line(1, at: 12345, discount: .percent(150)))
        #expect(total.net == .zero)
    }
}

@Suite("Sale totals")
struct SaleTotalsTests {
    // A: net 10 000 after a 2 000 amount discount. B: net 5 000. Sale discount 10% → 1 500.
    let cart = [
        line(2, at: 6000, discount: .amount(Money(2000))),
        line(1, at: 5000),
    ]

    @Test("nonPKP: no tax line at all")
    func none() {
        let totals = Pricing.totals(lines: cart, saleDiscount: .percent(10), tax: .nonPKP)
        #expect(totals == SaleTotals(
            subtotal: Money(15000), lineDiscounts: Money(2000), saleDiscount: Money(1500),
            taxable: .zero, tax: .zero, grandTotal: Money(13500)
        ))
    }

    @Test("Exclusive: tax is added on top of the discounted total")
    func exclusiveMode() {
        let totals = Pricing.totals(lines: cart, saleDiscount: .percent(10), tax: exclusive)
        #expect(totals.taxable == Money(13500))
        #expect(totals.tax == Money(1485))
        #expect(totals.grandTotal == Money(14985))
    }

    @Test("Exclusive single lines", arguments: [(10000, "1100", "11100"), (12345, "1357.95", "13702.95")])
    func exclusiveSingles(price: Int, tax: String, grand: String) throws {
        let totals = Pricing.totals(lines: [line(1, at: Decimal(price))], saleDiscount: .none, tax: exclusive)
        #expect(try totals.tax == money(tax))
        #expect(try totals.grandTotal == money(grand))
    }

    @Test("Inclusive: the customer pays the shelf price; base + tax == gross")
    func inclusiveMode() {
        let totals = Pricing.totals(lines: cart, saleDiscount: .percent(10), tax: inclusive)
        #expect(totals.grandTotal == Money(13500))
        #expect(totals.taxable + totals.tax == Money(13500))
    }

    @Test("Inclusive single lines", arguments: [
        (11100, "1100", "10000"), (10000, "990.99", "9009.01"),
        (12350, "1223.87", "11126.13"), (100_000, "9909.91", "90090.09"),
    ])
    func inclusiveSingles(price: Int, tax: String, base: String) throws {
        let totals = Pricing.totals(lines: [line(1, at: Decimal(price))], saleDiscount: .none, tax: inclusive)
        #expect(try totals.tax == money(tax))
        #expect(try totals.taxable == money(base))
        #expect(totals.grandTotal == Money(Decimal(price)))
    }

    @Test("Inclusive uses tax = round(gross − gross/(1+rate)), which differs from base × rate", arguments: [
        (10007, "991.68", "9015.32"), (50, "4.95", "45.05"), (61, "6.05", "54.95"),
    ])
    func inclusiveDivergesFromNaive(price: Int, tax: String, base: String) throws {
        let totals = Pricing.totals(lines: [line(1, at: Decimal(price))], saleDiscount: .none, tax: inclusive)
        #expect(try totals.tax == money(tax))
        #expect(try totals.taxable == money(base))
        #expect(totals.taxable + totals.tax == Money(Decimal(price)))
        let naive = try Rounding.bankers(totals.taxable.amount * dec("0.11"), scale: 2)
        #expect(naive != totals.tax.amount)
    }

    @Test("Mixed cart: the sale discount is shared in proportion to line net")
    func mixedTaxability() throws {
        let mixed = [
            line(2, at: 6000, discount: .amount(Money(2000))), // taxable, net 10 000
            line(1, at: 5000, taxable: false), // net 5 000
        ]
        // Sale discount 1 500; non-taxable share 500; taxable portion 9 000.
        let exclusiveTotals = Pricing.totals(lines: mixed, saleDiscount: .percent(10), tax: exclusive)
        #expect(exclusiveTotals.taxable == Money(9000))
        #expect(exclusiveTotals.tax == Money(990))
        #expect(exclusiveTotals.grandTotal == Money(14490))

        let inclusiveTotals = Pricing.totals(lines: mixed, saleDiscount: .percent(10), tax: inclusive)
        #expect(try inclusiveTotals.tax == money("891.89"))
        #expect(try inclusiveTotals.taxable == money("8108.11"))
        #expect(inclusiveTotals.grandTotal == Money(13500))

        #expect(Pricing.totals(lines: mixed, saleDiscount: .percent(10), tax: .nonPKP).grandTotal == Money(13500))
    }

    @Test("Mixed cart with an uneven split rounds the non-taxable share and keeps the remainder")
    func mixedTaxabilityUnevenSplit() throws {
        let mixed = [line(1, at: 7777), line(1, at: 3333, taxable: false)]
        // Sale discount 777.7; non-taxable share 233.31; taxable portion 7 232.61.
        let exclusiveTotals = Pricing.totals(lines: mixed, saleDiscount: .percent(7), tax: exclusive)
        #expect(try exclusiveTotals.saleDiscount == money("777.7"))
        #expect(try exclusiveTotals.taxable == money("7232.61"))
        #expect(try exclusiveTotals.tax == money("795.59"))

        let inclusiveTotals = Pricing.totals(lines: mixed, saleDiscount: .percent(7), tax: inclusive)
        #expect(try inclusiveTotals.tax == money("716.75"))
        #expect(try inclusiveTotals.taxable == money("6515.86"))
    }

    @Test("Empty cart and a 100% sale discount are all zeros, no division by zero")
    func edges() {
        let empty = Pricing.totals(lines: [], saleDiscount: .percent(10), tax: inclusive)
        #expect(empty.grandTotal == .zero && empty.tax == .zero && empty.taxable == .zero)
        let free = Pricing.totals(lines: cart, saleDiscount: .percent(100), tax: inclusive)
        #expect(free.grandTotal == .zero && free.tax == .zero)
    }
}
