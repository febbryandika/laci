import Foundation
import SwiftData

/// What a catalogue import would do, per row, before anything is written (SPEC §3.2).
public struct ImportPreview: Hashable, Sendable {
    public let added: [CatalogueRow]
    public let updated: [CatalogueRow]
    public let rejected: [ImportRejection]

    public init(added: [CatalogueRow], updated: [CatalogueRow], rejected: [ImportRejection]) {
        self.added = added
        self.updated = updated
        self.rejected = rejected
    }
}

/// Preview-then-commit. The preview is pure classification against the current store; the commit
/// re-checks barcode ownership row by row and applies the whole preview or nothing.
@MainActor
public final class CatalogueImporter {
    private let products: any ProductRepository
    private let transactor: Transactor
    private var context: ModelContext {
        transactor.context
    }

    public init(products: any ProductRepository, transactor: Transactor) {
        self.products = products
        self.transactor = transactor
    }

    public func preview(_ parsed: CatalogueCSV.Parsed) throws -> ImportPreview {
        var added: [CatalogueRow] = []
        var updated: [CatalogueRow] = []
        var rejected = parsed.rejected
        for row in parsed.rows {
            if let clash = try barcodeClash(row) {
                rejected.append(ImportRejection(
                    line: row.line, sku: row.sku, reason: .barcodeTaken(value: clash.value, bySKU: clash.owner)
                ))
            } else if try products.product(sku: row.sku) != nil {
                updated.append(row)
            } else {
                added.append(row)
            }
        }
        return ImportPreview(added: added, updated: updated, rejected: rejected.sorted { $0.line < $1.line })
    }

    /// Added rows take their stock from the file as a `stock_in` movement. Updated rows never touch
    /// stock: it is a counter, and counters move through movements (SPEC §5.5).
    ///
    /// The store is read once, before the first insert. A fetch against a context that holds the
    /// batch's unsaved inserts costs time in proportion to them, so looking each row up as it went
    /// made the commit quadratic: 4,000 rows took about 100 s. The checks are the repositories'
    /// own (a taken SKU, a taken barcode, a missing product) and throw the same errors, so anything
    /// that changed between preview and commit still rolls the whole batch back.
    public func commit(_ preview: ImportPreview, now: Date) throws {
        try transactor.perform {
            var index = try Index(context)
            for row in preview.added {
                try add(row, now: now, index: &index)
            }
            for row in preview.updated {
                try update(row, now: now, index: &index)
            }
        }
    }

    /// What the store held when the commit began, kept current as the batch inserts.
    private struct Index {
        var products: [String: Product]
        /// Barcode value to the SKU that owns it.
        var barcodes: [String: String]

        init(_ context: ModelContext) throws {
            products = try Dictionary(
                context.fetch(FetchDescriptor<Product>()).map { ($0.sku, $0) }, uniquingKeysWith: { first, _ in first }
            )
            barcodes = try Dictionary(
                context.fetch(FetchDescriptor<Barcode>()).map { ($0.value, $0.product?.sku ?? "") },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }

    private func add(_ row: CatalogueRow, now: Date, index: inout Index) throws {
        guard index.products[row.sku] == nil else { throw CoreError.skuTaken(row.sku) }
        let product = Product(
            sku: row.sku, name: row.name, unit: row.unit, cost: row.cost, price: row.price,
            tracksStock: row.tracksStock, updatedAt: now
        )
        context.insert(product)
        index.products[row.sku] = product
        try addBarcodes(row.barcodes, to: product, index: &index)
        if row.stockOnHand != 0 {
            product.stockOnHand += row.stockOnHand
            context.insert(StockMovement(
                productSKU: row.sku, delta: row.stockOnHand, reason: .stockIn, occurredAt: now, saleID: nil
            ))
        }
    }

    private func update(_ row: CatalogueRow, now: Date, index: inout Index) throws {
        guard let product = index.products[row.sku] else { throw CoreError.productNotFound(sku: row.sku) }
        product.name = row.name
        product.unit = row.unit
        product.cost = row.cost
        product.price = row.price
        product.tracksStock = row.tracksStock
        try products.update(product, updatedAt: now)
        try addBarcodes(row.barcodes.filter { index.barcodes[$0] != row.sku }, to: product, index: &index)
    }

    private func addBarcodes(_ values: [String], to product: Product, index: inout Index) throws {
        for value in values {
            if let owner = index.barcodes[value] {
                throw CoreError.barcodeTaken(value: value, existingSKU: owner)
            }
            // The parser already rejected bad check digits, so inference cannot fail here.
            let barcode = Barcode(value: value, symbology: Symbology.inferred(from: value) ?? .code128)
            context.insert(barcode)
            barcode.product = product
            index.barcodes[value] = product.sku
        }
    }

    private func barcodeClash(_ row: CatalogueRow) throws -> (value: String, owner: String)? {
        for value in row.barcodes {
            if case let .product(owner) = try products.lookup(scannedCode: value), owner.sku != row.sku {
                return (value, owner.sku)
            }
        }
        return nil
    }
}

@MainActor
public extension CatalogueRow {
    /// A stored product as an export row. `line` is 0: the row did not come from a file.
    init(_ product: Product) {
        self.init(
            line: 0, sku: product.sku, name: product.name, unit: product.unit, cost: product.cost,
            price: product.price, tracksStock: product.tracksStock, stockOnHand: product.stockOnHand,
            barcodes: product.barcodes.map(\.value).sorted()
        )
    }
}
