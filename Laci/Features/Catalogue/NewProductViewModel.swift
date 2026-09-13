import Foundation
import LaciCore
import Observation

/// "Create SKU with this barcode" (SPEC §3.1.2): the smallest form that yields a sellable product.
/// Product and barcode are written in one transaction, so a taken SKU or barcode leaves nothing
/// behind. The full catalogue screen is a later phase.
@MainActor
@Observable
final class NewProductViewModel {
    let barcode: PendingBarcode
    var sku: String
    var name = ""
    var unit = "pcs"
    var priceText = ""
    var costText = "0"
    var stockText = "0"
    var tracksStock = true
    private(set) var error: String?

    private let products: any ProductRepository
    private let transactor: Transactor
    private let now: () -> Date

    init(barcode: PendingBarcode, dependencies: Dependencies, now: @escaping () -> Date = { Date() }) {
        self.barcode = barcode
        // The barcode is the SKU most shops use; it is editable.
        sku = barcode.value
        products = dependencies.products
        transactor = dependencies.transactor
        self.now = now
    }

    func save() -> Product? {
        let sku = sku.trimmingCharacters(in: .whitespaces)
        let name = name.trimmingCharacters(in: .whitespaces)
        let unit = unit.trimmingCharacters(in: .whitespaces)
        guard !sku.isEmpty else { return fail("SKU wajib diisi") }
        guard !name.isEmpty else { return fail("Nama wajib diisi") }
        guard let price = DecimalInput.parse(priceText) else { return fail("Harga jual tidak valid") }
        guard let cost = DecimalInput.parse(costText) else { return fail("Modal tidak valid") }
        guard let stock = DecimalInput.parse(stockText) else { return fail("Stok awal tidak valid") }
        let product = Product(
            sku: sku, name: name, unit: unit.isEmpty ? "pcs" : unit, cost: cost, price: price,
            tracksStock: tracksStock, stockOnHand: tracksStock ? stock : 0, updatedAt: now()
        )
        do {
            try transactor.perform {
                try products.create(product)
                try products.addBarcode(barcode.value, symbology: barcode.symbology, to: sku)
            }
        } catch CoreError.skuTaken {
            return fail("SKU sudah dipakai")
        } catch let CoreError.barcodeTaken(_, existingSKU) {
            return fail("Barcode sudah dipakai SKU \(existingSKU)")
        } catch {
            return fail("Gagal menyimpan produk")
        }
        error = nil
        return product
    }

    private func fail(_ message: String) -> Product? {
        error = message
        return nil
    }
}
