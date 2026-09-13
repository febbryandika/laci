import Foundation
import LaciCore
import LaciMoney
import Observation
import os

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

/// A scanned code no product owns; "create SKU with this barcode" is prefilled from it (SPEC §3.1.2).
struct PendingBarcode: Hashable, Identifiable {
    let value: String
    let symbology: Symbology

    var id: String {
        value
    }
}

/// The sell screen's state. Every amount comes from `Pricing` or `Tender`; the only arithmetic
/// here is a quantity count going up or down by one.
@MainActor
@Observable
final class SellViewModel: ScanReceiving {
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
    private(set) var scanNotice: ScanNotice?
    private(set) var pendingBarcode: PendingBarcode?
    /// Counts accepted scans; the views key haptic and audible feedback on it.
    private(set) var scansAccepted = 0
    /// Shared with the camera controller so a deleted line can be re-scanned at once (SPEC §6).
    let scanDebouncer = ScanDebouncer(window: .milliseconds(1200))

    private let products: any ProductRepository
    private let sales: any SaleRepository
    private let closeOuts: any CloseOutRepository
    private let printer: PrinterCoordinator
    private let now: () -> Date
    private let signposter = OSSignposter(subsystem: "id.laci", category: "scan")
    private let log = Logger(subsystem: "id.laci", category: "scan")

    init(dependencies: Dependencies, now: @escaping () -> Date = { Date() }) {
        products = dependencies.products
        sales = dependencies.sales
        closeOuts = dependencies.closeOuts
        printer = dependencies.printer
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
        scanDebouncer.reset()
    }

    func clearTenderError() {
        tenderError = nil
    }

    // MARK: Scanning

    /// Every read lands here: camera, keyboard wedge and manual entry (SPEC §6). `symbology` is
    /// nil when no camera saw the code; it is then derived from the payload's shape.
    func didRead(code: String, symbology: Symbology?) {
        let interval = signposter.beginInterval("scan-to-cart")
        defer { signposter.endInterval("scan-to-cart", interval) }
        // A wedge sends the payload plus Return.
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        let lookup: ScanLookup
        do {
            lookup = try products.lookup(scannedCode: code)
        } catch {
            log.error("lookup failed: \(String(describing: error), privacy: .public)")
            scanNotice = .lookupFailed
            return
        }
        switch lookup {
        case let .product(product):
            add(product)
            scansAccepted += 1
            scanNotice = nil
            log.info("scan added \(product.sku, privacy: .private)")
        case .badChecksum:
            scanNotice = .scanAgain
            log.info("scan rejected: bad checksum")
        case .unknownProduct:
            scanNotice = nil
            pendingBarcode = PendingBarcode(value: code, symbology: symbology ?? Self.symbology(of: code))
            log.info("scan unknown \(code, privacy: .private)")
        }
    }

    func clearScanNotice() {
        scanNotice = nil
    }

    func clearPendingBarcode() {
        pendingBarcode = nil
    }

    /// A wedge or typed payload carries no type: EAN shapes are recognised, and anything else is
    /// recorded as Code 128, which is what those scanners read off a non-EAN label.
    private static func symbology(of code: String) -> Symbology {
        if case let .valid(symbology) = EAN.validate(code) {
            return symbology
        }
        return .code128
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
        let sale: Sale
        do {
            sale = try sales.commit(draft, tradingDay: ShopDefaults.tradingDay, timeZone: ShopDefaults.timeZone)
        } catch {
            tenderError = .commitFailed
            return
        }
        lastSale = sale
        lines = []
        saleDiscount = .none
        query = ""
        tenderError = nil
        // Last, and never awaited: the sale is saved and the cart is clear whatever the printer does
        // (SPEC §7.3).
        printer.printReceipt(for: sale)
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
