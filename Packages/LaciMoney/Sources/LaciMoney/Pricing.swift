import Foundation

public enum Pricing {
    public static func total(for line: CartLine) -> LineTotal {
        let gross = Money(Rounding.bankers(line.unitPrice.times(line.quantity).amount, scale: 2))
        let discount = line.discount.applied(to: gross)
        return LineTotal(gross: gross, discount: discount, net: gross - discount)
    }

    public static func totals(lines: [CartLine], saleDiscount: Discount, tax: TaxPolicy) -> SaleTotals {
        var subtotal = Money.zero
        var lineDiscounts = Money.zero
        var nonTaxableNet = Money.zero
        for line in lines {
            let lineTotal = total(for: line)
            subtotal += lineTotal.net
            lineDiscounts += lineTotal.discount
            if !line.taxable {
                nonTaxableNet += lineTotal.net
            }
        }

        let saleDiscountAmount = saleDiscount.applied(to: subtotal)
        let afterSaleDiscount = subtotal - saleDiscountAmount

        // The sale discount is shared across lines in proportion to their net. Rounding the
        // non-taxable share and giving the taxable side the remainder keeps the two shares summing
        // to the discount exactly, and an all-taxable cart never divides at all.
        let nonTaxableShare = subtotal == .zero
            ? Money.zero
            : Money(Rounding.bankers(saleDiscountAmount.amount * nonTaxableNet.amount / subtotal.amount, scale: 2))
        let taxablePortion = (subtotal - nonTaxableNet) - (saleDiscountAmount - nonTaxableShare)

        let taxable: Money
        let taxAmount: Money
        let grandTotal: Money
        switch tax.mode {
        case .none:
            taxable = .zero
            taxAmount = .zero
            grandTotal = afterSaleDiscount
        case .exclusive:
            taxable = taxablePortion
            taxAmount = Money(Rounding.bankers(taxablePortion.amount * tax.rate, scale: 2))
            grandTotal = afterSaleDiscount + taxAmount
        case .inclusive:
            // tax = round(gross − gross / (1 + rate)); base = gross − tax. Deriving the base from the
            // tax makes base + tax == gross an invariant rather than a hope (SPEC §8.2).
            let gross = taxablePortion.amount
            taxAmount = Money(Rounding.bankers(gross - gross / (1 + tax.rate), scale: 2))
            taxable = taxablePortion - taxAmount
            grandTotal = afterSaleDiscount
        }

        return SaleTotals(
            subtotal: subtotal,
            lineDiscounts: lineDiscounts,
            saleDiscount: saleDiscountAmount,
            taxable: taxable,
            tax: taxAmount,
            grandTotal: grandTotal
        )
    }
}
