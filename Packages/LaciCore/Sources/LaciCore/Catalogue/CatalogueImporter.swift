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
    private let stock: any StockRepository
    private let transactor: Transactor

    public init(products: any ProductRepository, stock: any StockRepository, transactor: Transactor) {
        self.products = products
        self.stock = stock
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
    public func commit(_ preview: ImportPreview, now: Date) throws {
        try transactor.perform {
            for row in preview.added {
                try add(row, now: now)
            }
            for row in preview.updated {
                try update(row, now: now)
            }
        }
    }

    private func add(_ row: CatalogueRow, now: Date) throws {
        let product = Product(
            sku: row.sku, name: row.name, unit: row.unit, cost: row.cost, price: row.price,
            tracksStock: row.tracksStock, updatedAt: now
        )
        try products.create(product)
        try addBarcodes(row.barcodes, to: row.sku)
        if row.stockOnHand != 0 {
            try stock.adjust(sku: row.sku, delta: row.stockOnHand, reason: .stockIn, occurredAt: now)
        }
    }

    private func update(_ row: CatalogueRow, now: Date) throws {
        let product = try transactor.context.requireProduct(sku: row.sku)
        product.name = row.name
        product.unit = row.unit
        product.cost = row.cost
        product.price = row.price
        product.tracksStock = row.tracksStock
        try products.update(product, updatedAt: now)
        let existing = Set(product.barcodes.map(\.value))
        try addBarcodes(row.barcodes.filter { !existing.contains($0) }, to: row.sku)
    }

    private func addBarcodes(_ values: [String], to sku: String) throws {
        for value in values {
            // The parser already rejected bad check digits, so inference cannot fail here.
            let symbology = Symbology.inferred(from: value) ?? .code128
            try products.addBarcode(value, symbology: symbology, to: sku)
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

public extension CatalogueRow {
    /// A stored product as an export row. `line` is 0: the row did not come from a file.
    @MainActor
    init(_ product: Product) {
        self.init(
            line: 0, sku: product.sku, name: product.name, unit: product.unit, cost: product.cost,
            price: product.price, tracksStock: product.tracksStock, stockOnHand: product.stockOnHand,
            barcodes: product.barcodes.map(\.value).sorted()
        )
    }
}
