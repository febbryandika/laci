import Foundation
@testable import Laci
import LaciCore
import Testing

private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
private let pending = PendingBarcode(value: "8992761111083", symbology: .ean13)

@MainActor
@Suite("New product from a barcode")
struct NewProductViewModelTests {
    let dependencies: Dependencies
    let viewModel: NewProductViewModel

    init() throws {
        dependencies = try Dependencies.inMemory()
        viewModel = NewProductViewModel(barcode: pending, dependencies: dependencies, now: { fixedNow })
    }

    @Test("The SKU is prefilled with the barcode, and saving creates product and barcode together")
    func saveCreatesBoth() throws {
        #expect(viewModel.sku == pending.value)
        viewModel.name = " Indomie Goreng "
        viewModel.priceText = "3500"
        viewModel.costText = "3000"
        viewModel.stockText = "24"
        let product = try #require(viewModel.save())
        #expect(product.name == "Indomie Goreng")
        #expect(product.unit == "pcs")
        #expect(product.stockOnHand == 24)
        #expect(viewModel.error == nil)
        guard case let .product(found) = try dependencies.products.lookup(scannedCode: pending.value) else {
            Issue.record("expected the barcode to resolve to the new product")
            return
        }
        #expect(found.sku == pending.value)
    }

    @Test("Untracked stock is stored as zero whatever was typed")
    func untrackedStock() throws {
        viewModel.name = "Pulsa 10k"
        viewModel.priceText = "12000"
        viewModel.stockText = "99"
        viewModel.tracksStock = false
        let product = try #require(viewModel.save())
        #expect(product.tracksStock == false)
        #expect(product.stockOnHand == 0)
    }

    @Test("A taken SKU is refused and the barcode stays unattached")
    func skuTaken() throws {
        let existing = Product(
            sku: "X", name: "Existing", unit: "pcs", cost: 0, price: 1000, tracksStock: false, updatedAt: fixedNow
        )
        try dependencies.products.create(existing)
        viewModel.sku = "X"
        viewModel.name = "Other"
        viewModel.priceText = "2000"
        #expect(viewModel.save() == nil)
        #expect(viewModel.error == "SKU sudah dipakai")
        guard case .unknownProduct = try dependencies.products.lookup(scannedCode: pending.value) else {
            Issue.record("expected the barcode to remain unknown")
            return
        }
    }

    @Test("A barcode another SKU owns is refused and the new product is rolled back")
    func barcodeTaken() throws {
        let existing = Product(
            sku: "B", name: "Owner", unit: "pcs", cost: 0, price: 1000, tracksStock: false, updatedAt: fixedNow
        )
        try dependencies.products.create(existing)
        try dependencies.products.addBarcode(pending.value, symbology: .ean13, to: "B")
        viewModel.sku = "NEW"
        viewModel.name = "Other"
        viewModel.priceText = "2000"
        #expect(viewModel.save() == nil)
        #expect(viewModel.error == "Barcode sudah dipakai SKU B")
        let created = try dependencies.products.product(sku: "NEW")
        #expect(created == nil)
    }

    @Test("Missing name or an unparsable price is refused before anything is written")
    func validation() throws {
        viewModel.priceText = "3500"
        #expect(viewModel.save() == nil)
        #expect(viewModel.error == "Nama wajib diisi")
        viewModel.name = "Item"
        viewModel.priceText = "3.5.0"
        #expect(viewModel.save() == nil)
        #expect(viewModel.error == "Harga jual tidak valid")
        let all = try dependencies.products.all(includeArchived: true)
        #expect(all.isEmpty)
    }

    @Test("Without a barcode the SKU is typed and only the product is written")
    func withoutBarcode() throws {
        let viewModel = NewProductViewModel(barcode: nil, dependencies: dependencies, now: { fixedNow })
        #expect(viewModel.sku.isEmpty)
        viewModel.sku = "A1"
        viewModel.name = "Aqua"
        viewModel.priceText = "3500"
        let product = try #require(viewModel.save())
        #expect(product.sku == "A1")
        #expect(product.barcodes.isEmpty)
        let stored = try dependencies.products.product(sku: "A1")
        #expect(stored != nil)
    }
}
