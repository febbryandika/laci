import Foundation
import LaciCore
import LaciMoney
import Observation

/// Why a checkout was refused. Decided here, in the view model, so a short tender never reaches
/// the repository (SPEC §3.1.5). The view owns the wording.
enum TenderError: Hashable {
    case emptyCart
    case cashShort(rounded: Money)
    case missingReference
    case commitFailed
}

/// The two tenders that need a reference instead of cash (SPEC §1). Cash has its own path.
enum NonCashMethod: String, Hashable, CaseIterable {
    case qris
    case transfer
}

/// The sell screen's state. Every amount comes from `Pricing` or `Tender`; the only arithmetic
/// here is a quantity count going up or down by one.
@MainActor
@Observable
final class SellViewModel {
    private(set) var catalogue: [Product] = []
    private(set) var catalogueFailed = false
    var query = ""
    /// One line per SKU; adding a SKU already present increments it (SPEC §3.1.3).
    private(set) var lines: [SaleDraft.Line] = []
    private(set) var saleDiscount: Discount = .none
    private(set) var tenderError: TenderError?
    private(set) var lastSale: Sale?
    /// An earlier trading day that was never closed (SPEC §3.3.5); the sell screen banners it.
    private(set) var openPriorDay: Date?

    private let products: any ProductRepository
    private let sales: any SaleRepository
    private let closeOuts: any CloseOutRepository
    private let now: () -> Date

    init(dependencies: Dependencies, now: @escaping () -> Date = { Date() }) {
        products = dependencies.products
        sales = dependencies.sales
        closeOuts = dependencies.closeOuts
        self.now = now
    }

    // MARK: Catalogue

    var results: [Product] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return catalogue }
        return catalogue.filter {
            $0.name.localizedCaseInsensitiveContains(needle) || $0.sku.localizedCaseInsensitiveContains(needle)
        }
    }

    func loadCatalogue() {
        do {
            catalogue = try products.all(includeArchived: false)
            catalogueFailed = false
        } catch {
            catalogue = []
            catalogueFailed = true
        }
    }

    // MARK: Close-out

    func refreshCloseOutStatus() {
        let today = ShopDefaults.tradingDay.bucket(for: now(), timeZone: ShopDefaults.timeZone)
        let target = CloseOutViewModel.targetDay(latest: try? closeOuts.latest()?.tradingDay, today: today)
        openPriorDay = target < today ? target : nil
    }

    // MARK: Totals

    var totals: SaleTotals {
        Pricing.totals(lines: lines.map(\.cart), saleDiscount: saleDiscount, tax: ShopDefaults.taxPolicy)
    }

    var cashTotal: Money {
        Tender.roundForCash(totals.grandTotal)
    }

    var cashSuggestions: [Money] {
        Tender.suggestions(for: totals.grandTotal)
    }

    func lineTotal(for line: SaleDraft.Line) -> LineTotal {
        Pricing.total(for: line.cart)
    }

    func settle(tendered: Money) -> CashSettlement? {
        Tender.settle(total: totals.grandTotal, tendered: tendered)
    }

    // MARK: Cart

    func line(sku: String) -> SaleDraft.Line? {
        lines.first { $0.cart.sku == sku }
    }

    /// The single entry point for a product reaching the cart; the scanner will call it too.
    func add(_ product: Product) {
        if line(sku: product.sku) != nil {
            increment(sku: product.sku)
            return
        }
        let price = Money(product.price)
        // `taxable` is inert under `TaxPolicy.nonPKP`, and the schema has no per-product flag yet.
        let cart = CartLine(
            sku: product.sku, name: product.name, quantity: 1, unitPrice: price, discount: .none, taxable: true
        )
        lines.append(SaleDraft.Line(cart: cart, listPrice: price))
    }

    /// The keyboard path: Return in the search field adds the top match.
    func addFirstResult() {
        guard !query.isEmpty, let first = results.first else { return }
        add(first)
        query = ""
    }

    func increment(sku: String) {
        replace(sku: sku) { $0.with(quantity: $0.quantity + 1) }
    }

    func decrement(sku: String) {
        replace(sku: sku) { $0.quantity > 1 ? $0.with(quantity: $0.quantity - 1) : $0 }
    }

    func setQuantity(sku: String, _ quantity: Decimal) {
        guard quantity > 0 else { return }
        replace(sku: sku) { $0.with(quantity: quantity) }
    }

    func setUnitPrice(sku: String, _ price: Money) {
        guard price >= .zero else { return }
        replace(sku: sku) { $0.with(unitPrice: price) }
    }

    func setDiscount(sku: String, _ discount: Discount) {
        guard Self.isAllowed(discount) else { return }
        replace(sku: sku) { $0.with(discount: discount) }
    }

    func setSaleDiscount(_ discount: Discount) {
        guard Self.isAllowed(discount) else { return }
        saleDiscount = discount
    }

    func remove(sku: String) {
        lines.removeAll { $0.cart.sku == sku }
    }

    func clearTenderError() {
        tenderError = nil
    }

    // MARK: Checkout

    func checkoutCash(tendered: Money) {
        guard !lines.isEmpty else {
            tenderError = .emptyCart
            return
        }
        let totals = totals
        guard let settlement = Tender.settle(total: totals.grandTotal, tendered: tendered) else {
            tenderError = .cashShort(rounded: Tender.roundForCash(totals.grandTotal))
            return
        }
        commit(.cash(settlement), totals: totals)
    }

    func checkoutNonCash(_ method: NonCashMethod, reference: String) {
        guard !lines.isEmpty else {
            tenderError = .emptyCart
            return
        }
        let reference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty else {
            tenderError = .missingReference
            return
        }
        switch method {
        case .qris: commit(.qris(reference: reference), totals: totals)
        case .transfer: commit(.transfer(reference: reference), totals: totals)
        }
    }

    /// `Discount.applied` clamps a percent to 0...100 but takes an amount as given, and a negative
    /// amount would raise the line. Refused here, before it can reach the cart.
    private static func isAllowed(_ discount: Discount) -> Bool {
        switch discount {
        case .none, .percent: true
        case let .amount(money): money >= .zero
        }
    }

    private func replace(sku: String, _ transform: (CartLine) -> CartLine) {
        guard let index = lines.firstIndex(where: { $0.cart.sku == sku }) else { return }
        let line = lines[index]
        lines[index] = SaleDraft.Line(cart: transform(line.cart), listPrice: line.listPrice)
    }

    private func commit(_ payment: SaleDraft.Payment, totals: SaleTotals) {
        let draft = SaleDraft(lines: lines, totals: totals, payment: payment, occurredAt: now())
        do {
            lastSale = try sales.commit(draft, tradingDay: ShopDefaults.tradingDay, timeZone: ShopDefaults.timeZone)
        } catch {
            tenderError = .commitFailed
            return
        }
        lines = []
        saleDiscount = .none
        query = ""
        tenderError = nil
    }
}

private extension CartLine {
    /// `CartLine` is immutable by design; an edit is a rebuilt line.
    func with(quantity: Decimal? = nil, unitPrice: Money? = nil, discount: Discount? = nil) -> CartLine {
        CartLine(
            sku: sku, name: name, quantity: quantity ?? self.quantity, unitPrice: unitPrice ?? self.unitPrice,
            discount: discount ?? self.discount, taxable: taxable
        )
    }
}
