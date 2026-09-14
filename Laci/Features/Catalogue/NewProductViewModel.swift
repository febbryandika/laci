import Foundation
import LaciCore
import Observation

/// "Create SKU with this barcode" (SPEC §3.1.2): the smallest form that yields a sellable product.
/// Product and barcode are written in one transaction, so a taken SKU or barcode leaves nothing
/// behind. With no barcode it is the catalogue's "add first product": the SKU is typed.
@MainActor
@Observable
final class NewProductViewModel {
    let barcode: PendingBarcode?
    var sku: String
    var name = ""
    var unit = "pcs"
    var priceText = ""
    var costText = "0"
    var stockText = "0"
    var tracksStock = true
    private(set) var error: NewProductError?

    private let products: any ProductRepository
    private let transactor: Transactor
    private let now: () -> Date

    init(barcode: PendingBarcode?, dependencies: Dependencies, now: @escaping () -> Date = { Date() }) {
        self.barcode = barcode
        // The barcode is the SKU most shops use; it is editable.
        sku = barcode?.value ?? ""
        products = dependencies.products
        transactor = dependencies.transactor
        self.now = now
    }

    func save() -> Product? {
        let sku = sku.trimmingCharacters(in: .whitespaces)
        let name = name.trimmingCharacters(in: .whitespaces)
        let unit = unit.trimmingCharacters(in: .whitespaces)
        guard !sku.isEmpty else { return fail(.skuRequired) }
        guard !name.isEmpty else { return fail(.nameRequired) }
        guard let price = DecimalInput.parse(priceText) else { return fail(.priceInvalid) }
        guard let cost = DecimalInput.parse(costText) else { return fail(.costInvalid) }
        guard let stock = DecimalInput.parse(stockText) else { return fail(.stockInvalid) }
        let product = Product(
            sku: sku, name: name, unit: unit.isEmpty ? "pcs" : unit, cost: cost, price: price,
            tracksStock: tracksStock, stockOnHand: tracksStock ? stock : 0, updatedAt: now()
        )
        do {
            try transactor.perform {
                try products.create(product)
                if let barcode {
                    try products.addBarcode(barcode.value, symbology: barcode.symbology, to: sku)
                }
            }
        } catch CoreError.skuTaken {
            return fail(.skuTaken)
        } catch let CoreError.barcodeTaken(_, existingSKU) {
            return fail(.barcodeTaken(sku: existingSKU))
        } catch {
            return fail(.saveFailed)
        }
        error = nil
        return product
    }

    private func fail(_ reason: NewProductError) -> Product? {
        error = reason
        return nil
    }
}

/// Why a product could not be saved; the form shows `message`.
enum NewProductError: Hashable {
    case skuRequired
    case nameRequired
    case priceInvalid
    case costInvalid
    case stockInvalid
    case skuTaken
    case barcodeTaken(sku: String)
    case saveFailed

    var message: LocalizedStringResource {
        switch self {
        case .skuRequired: "SKU wajib diisi"
        case .nameRequired: "Nama wajib diisi"
        case .priceInvalid: "Harga jual tidak valid"
        case .costInvalid: "Modal tidak valid"
        case .stockInvalid: "Stok awal tidak valid"
        case .skuTaken: "SKU sudah dipakai"
        case let .barcodeTaken(sku): "Barcode sudah dipakai SKU \(sku)"
        case .saveFailed: "Gagal menyimpan produk"
        }
    }
}
