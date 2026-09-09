import Foundation
import LaciCore
import SwiftData
import Testing

@MainActor
@Suite("Product repository")
struct ProductRepositoryTests {
    let store: TestStore
    let repository: SwiftDataProductRepository
    let epoch = Date(timeIntervalSince1970: 0)

    init() throws {
        store = try TestStore()
        repository = SwiftDataProductRepository(transactor: Transactor(container: store.container))
    }

    @Test("A created product is found by SKU")
    func createThenFetch() throws {
        try repository.create(makeProduct("A"))
        let fetched = try #require(try repository.product(sku: "A"))
        #expect(fetched.name == "Item A")
    }

    @Test("A second product with the same SKU is rejected")
    func duplicateSKU() throws {
        try repository.create(makeProduct("A"))
        #expect(throws: CoreError.skuTaken("A")) { try repository.create(makeProduct("A", name: "Other")) }
        #expect(try repository.all(includeArchived: true).count == 1)
    }

    @Test("A barcode owned by one SKU cannot be claimed by another, and the owner is unchanged")
    func barcodeUniqueness() throws {
        try repository.create(makeProduct("A"))
        try repository.create(makeProduct("B"))
        try repository.addBarcode("5901234123457", symbology: .ean13, to: "A")

        #expect(throws: CoreError.barcodeTaken(value: "5901234123457", existingSKU: "A")) {
            try repository.addBarcode("5901234123457", symbology: .ean13, to: "B")
        }

        // A fresh context proves nothing was upserted underneath the check.
        let fresh = ModelContext(store.container)
        let barcodes = try fresh.fetch(FetchDescriptor<Barcode>())
        #expect(barcodes.count == 1)
        #expect(barcodes.first?.product?.sku == "A")
        let productB = try #require(try repository.product(sku: "B"))
        #expect(productB.barcodes.isEmpty)
    }

    @Test("A scan of an owned barcode finds the product")
    func lookupOwned() throws {
        try repository.create(makeProduct("A"))
        try repository.addBarcode("5901234123457", symbology: .ean13, to: "A")
        guard case let .product(found) = try repository.lookup(scannedCode: "5901234123457") else {
            Issue.record("expected .product")
            return
        }
        #expect(found.sku == "A")
    }

    @Test("A valid EAN nobody owns is an unknown product")
    func lookupUnknown() throws {
        guard case .unknownProduct = try repository.lookup(scannedCode: "8992761111083") else {
            Issue.record("expected .unknownProduct")
            return
        }
    }

    @Test("A misread digit is reported as a bad checksum, never as an unknown product")
    func lookupBadChecksum() throws {
        try repository.create(makeProduct("A"))
        try repository.addBarcode("5901234123457", symbology: .ean13, to: "A")
        guard case .badChecksum = try repository.lookup(scannedCode: "5901234123458") else {
            Issue.record("expected .badChecksum")
            return
        }
    }

    @Test("A non-EAN payload is looked up as-is")
    func lookupCode128() throws {
        try repository.create(makeProduct("A"))
        try repository.addBarcode("ABC-99", symbology: .code128, to: "A")
        guard case let .product(found) = try repository.lookup(scannedCode: "ABC-99") else {
            Issue.record("expected .product")
            return
        }
        #expect(found.sku == "A")
    }

    @Test("Adding a barcode to a missing SKU fails")
    func barcodeForMissingProduct() throws {
        #expect(throws: CoreError.productNotFound(sku: "ZZ")) {
            try repository.addBarcode("5901234123457", symbology: .ean13, to: "ZZ")
        }
    }

    @Test("Archived products are hidden unless asked for, and listing is sorted by name")
    func archiveAndList() throws {
        try repository.create(makeProduct("B", name: "Beras"))
        try repository.create(makeProduct("A", name: "Aqua"))
        try repository.archive(sku: "B", updatedAt: epoch)

        #expect(try repository.all(includeArchived: false).map(\.sku) == ["A"])
        #expect(try repository.all(includeArchived: true).map(\.sku) == ["A", "B"])
        #expect(try repository.product(sku: "B")?.isArchived == true)
    }

    @Test("Update persists the mutated model and stamps updatedAt")
    func update() throws {
        try repository.create(makeProduct("A"))
        let product = try #require(try repository.product(sku: "A"))
        product.price = 2500
        let later = Date(timeIntervalSince1970: 60)
        try repository.update(product, updatedAt: later)

        let fresh = ModelContext(store.container)
        let fetched = try #require(try fresh.fetch(FetchDescriptor<Product>()).first)
        #expect(fetched.price == 2500)
        #expect(fetched.updatedAt == later)
    }
}
