import Foundation
import LaciCore
import LaciMoney
import Observation
import os

/// One counted SKU (SPEC §3.2). `systemQuantity` is stock on hand at the first scan, so a sale
/// rung up mid-count on another screen does not silently move the variance.
struct StocktakeRow: Hashable, Identifiable {
    let sku: String
    let name: String
    let unit: String
    let systemQuantity: Decimal
    let cost: Money
    var countedText: String

    var id: String {
        sku
    }

    var counted: Decimal? {
        DecimalInput.parse(countedText)
    }

    var variance: Decimal? {
        counted.map { $0 - systemQuantity }
    }

    /// Variance valued at cost: what the missing or surplus stock is worth to the shop.
    var varianceValue: Money? {
        variance.map { cost.times($0) }
    }
}

enum StocktakeError: Hashable {
    case invalidCount(sku: String)
    case applyFailed
}

/// The scan-through count. Every scan lands in `didRead` like the sell screen's: a first scan
/// lists the SKU counted once, a later scan of the same SKU counts one more, and the count is
/// editable. Applying writes one `stocktake` batch for the rows that differ and nothing for the
/// SKUs never scanned: a partial count is the normal case (SPEC §3.2).
@MainActor
@Observable
final class StocktakeViewModel: ScanReceiving {
    private(set) var rows: [StocktakeRow] = []
    private(set) var error: StocktakeError?
    /// How many SKUs the last apply moved; nil until one has run.
    private(set) var appliedCount: Int?
    private(set) var scanNotice: ScanNotice?
    private(set) var scansAccepted = 0
    let scanDebouncer = ScanDebouncer(window: .milliseconds(1200))

    private let products: any ProductRepository
    private let stock: any StockRepository
    private let now: () -> Date
    private let log = Logger(subsystem: "id.laci", category: "stocktake")

    init(dependencies: Dependencies, now: @escaping () -> Date = { Date() }) {
        products = dependencies.products
        stock = dependencies.stock
        self.now = now
    }

    var totalVarianceValue: Money {
        rows.compactMap(\.varianceValue).reduce(.zero, +)
    }

    var hasInvalidRows: Bool {
        rows.contains { $0.counted == nil }
    }

    var canApply: Bool {
        !rows.isEmpty && !hasInvalidRows
    }

    /// The rows whose count differs from the system figure: what an apply would write.
    var changedRows: [StocktakeRow] {
        rows.filter { ($0.variance ?? 0) != 0 }
    }

    // MARK: Scanning

    func didRead(code: String, symbology _: Symbology?) {
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
            count(product)
        case .badChecksum:
            scanNotice = .scanAgain
        case .unknownProduct:
            // A typed SKU is as good as a barcode on a count sheet.
            if let product = try? products.product(sku: code) {
                count(product)
            } else {
                scanNotice = .unknownProduct
                log.info("stocktake unknown \(code, privacy: .private)")
            }
        }
    }

    private func count(_ product: Product) {
        guard product.tracksStock else {
            scanNotice = .untrackedProduct
            return
        }
        if let index = rows.firstIndex(where: { $0.sku == product.sku }) {
            let counted = (rows[index].counted ?? 0) + 1
            rows[index].countedText = "\(counted)"
        } else {
            rows.append(StocktakeRow(
                sku: product.sku, name: product.name, unit: product.unit, systemQuantity: product.stockOnHand,
                cost: Money(product.cost), countedText: "1"
            ))
        }
        scansAccepted += 1
        scanNotice = nil
    }

    func clearScanNotice() {
        scanNotice = nil
    }

    // MARK: Editing

    func setCounted(_ text: String, for sku: String) {
        guard let index = rows.firstIndex(where: { $0.sku == sku }) else { return }
        rows[index].countedText = text
    }

    func remove(sku: String) {
        rows.removeAll { $0.sku == sku }
        // The item just removed can be scanned straight back in (SPEC §6).
        scanDebouncer.reset()
    }

    func remove(atOffsets offsets: IndexSet) {
        rows = rows.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        scanDebouncer.reset()
    }

    // MARK: Applying

    /// One batch or nothing. A count that matches the system figure writes no movement, and a
    /// count sheet with no differences is still a finished count: the list is cleared.
    @discardableResult
    func apply() -> Bool {
        if let invalid = rows.first(where: { $0.counted == nil }) {
            error = .invalidCount(sku: invalid.sku)
            return false
        }
        let adjustments = changedRows.compactMap { row in
            row.variance.map { StockAdjustment(sku: row.sku, delta: $0) }
        }
        do {
            if !adjustments.isEmpty {
                try stock.applyBatch(adjustments, reason: .stocktake, occurredAt: now())
            }
        } catch {
            log.error("stocktake apply failed: \(String(describing: error), privacy: .public)")
            self.error = .applyFailed
            return false
        }
        let counted = rows.count
        log.info("stocktake applied \(adjustments.count, privacy: .public) of \(counted, privacy: .public)")
        appliedCount = adjustments.count
        rows = []
        error = nil
        return true
    }

    func clear() {
        rows = []
        error = nil
        appliedCount = nil
    }

    func clearError() {
        error = nil
    }
}
