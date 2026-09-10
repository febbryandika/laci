import Foundation
import LaciCore
import LaciMoney
import LaciPrint

/// Sale → Receipt. Names, prices and discounts come from the stored lines so a reprint says what it
/// said; only the unit is read from the catalogue, because `SaleLine` never stored one and a
/// missing unit is cosmetic.
enum ReceiptFactory {
    static func make(_ sale: Sale, products: any ProductRepository, isReprint: Bool) -> Receipt {
        let lines = sale.lines.sorted { $0.name < $1.name }
        let lineDiscounts = lines.reduce(Decimal.zero) { $0 + $1.discountAmount }
        let taxPolicy = ShopDefaults.taxPolicy
        return Receipt(
            shopName: ShopDefaults.shopName,
            shopLines: ShopDefaults.shopLines,
            footerLines: ShopDefaults.footerLines,
            number: sale.number,
            occurredAt: sale.occurredAt,
            timeZone: ShopDefaults.timeZone,
            lines: lines.map { line in
                Receipt.Line(
                    name: line.name, quantity: line.quantity,
                    unit: (try? products.product(sku: line.productSKU))??.unit ?? "",
                    unitPrice: Money(line.unitPrice), discount: Money(line.discountAmount)
                )
            },
            subtotal: Money(sale.subtotal),
            saleDiscount: Money(sale.discountTotal - lineDiscounts),
            taxTotal: Money(sale.taxTotal),
            taxRate: taxPolicy.mode == .none ? nil : taxPolicy.rate,
            roundingDelta: Money(sale.roundingDelta),
            total: Money(sale.total),
            tender: tender(of: sale),
            isReprint: isReprint,
            logo: nil
        )
    }

    /// A cash sale with missing amounts, or a method this build does not know, prints as cash for
    /// the total rather than not at all.
    private static func tender(of sale: Sale) -> Receipt.Tender {
        switch sale.paymentMethod {
        case .qris: .qris(reference: sale.reference ?? "")
        case .transfer: .transfer(reference: sale.reference ?? "")
        case .cash, nil:
            .cash(tendered: Money(sale.amountTendered ?? sale.total), change: Money(sale.changeGiven ?? 0))
        }
    }
}
