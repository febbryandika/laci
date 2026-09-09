import Foundation
import SwiftData

/// What a scan resolves to. A bad checksum is its own case (SPEC §6): the cashier needs to know
/// whether to scan again or to create a product.
public enum ScanLookup {
    case product(Product)
    case unknownProduct
    case badChecksum
}

@MainActor
public protocol ProductRepository: AnyObject {
    func product(sku: String) throws -> Product?
    func lookup(scannedCode: String) throws -> ScanLookup
    /// Sorted by name.
    func all(includeArchived: Bool) throws -> [Product]
    func create(_ product: Product) throws
    func update(_ product: Product, updatedAt: Date) throws
    func addBarcode(_ value: String, symbology: Symbology, to sku: String) throws
    func archive(sku: String, updatedAt: Date) throws
}

@MainActor
public final class SwiftDataProductRepository: ProductRepository {
    private let transactor: Transactor
    private var context: ModelContext {
        transactor.context
    }

    public init(transactor: Transactor) {
        self.transactor = transactor
    }

    public func product(sku: String) throws -> Product? {
        try context.product(sku: sku)
    }

    public func lookup(scannedCode code: String) throws -> ScanLookup {
        if case .badChecksum = EAN.validate(code) {
            return .badChecksum
        }
        guard let product = try context.barcode(value: code)?.product else { return .unknownProduct }
        return .product(product)
    }

    public func all(includeArchived: Bool) throws -> [Product] {
        var descriptor = FetchDescriptor<Product>(sortBy: [SortDescriptor(\.name)])
        if !includeArchived {
            descriptor.predicate = #Predicate { !$0.isArchived }
        }
        return try context.fetch(descriptor)
    }

    /// `.unique` upserts silently on save, so uniqueness is checked here, before the insert.
    public func create(_ product: Product) throws {
        try transactor.perform {
            if try self.product(sku: product.sku) != nil {
                throw CoreError.skuTaken(product.sku)
            }
            context.insert(product)
        }
    }

    public func update(_ product: Product, updatedAt: Date) throws {
        try transactor.perform { product.updatedAt = updatedAt }
    }

    public func addBarcode(_ value: String, symbology: Symbology, to sku: String) throws {
        try transactor.perform {
            let product = try context.requireProduct(sku: sku)
            if let existing = try context.barcode(value: value) {
                throw CoreError.barcodeTaken(value: value, existingSKU: existing.product?.sku ?? "")
            }
            let barcode = Barcode(value: value, symbology: symbology)
            context.insert(barcode)
            barcode.product = product
        }
    }

    public func archive(sku: String, updatedAt: Date) throws {
        try transactor.perform {
            let product = try context.requireProduct(sku: sku)
            product.isArchived = true
            product.updatedAt = updatedAt
        }
    }
}
