import Foundation
@testable import Laci
import LaciCore
import Testing

private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor
@Suite("Catalogue view model")
struct CatalogueViewModelTests {
    let dependencies: Dependencies
    let viewModel: CatalogueViewModel

    init() throws {
        dependencies = try Dependencies.inMemory()
        viewModel = CatalogueViewModel(dependencies: dependencies)
        for (sku, name) in [("B2", "Beras Medium"), ("A1", "Aqua 600ml"), ("C3", "Kopi Kapal Api")] {
            try dependencies.products.create(Product(
                sku: sku, name: name, unit: "pcs", cost: 0, price: 1000, tracksStock: true, stockOnHand: 0,
                updatedAt: fixedNow
            ))
        }
    }

    @Test("Loading lists every product by name")
    func loads() {
        viewModel.load()
        #expect(viewModel.products.map(\.sku) == ["A1", "B2", "C3"])
        #expect(!viewModel.loadFailed)
    }

    @Test("The search matches name or SKU, case-insensitively")
    func search() {
        viewModel.load()
        viewModel.query = "kopi"
        #expect(viewModel.results.map(\.sku) == ["C3"])
        viewModel.query = "a1"
        #expect(viewModel.results.map(\.sku) == ["A1"])
        viewModel.query = "   "
        #expect(viewModel.results.count == 3)
    }

    @Test("The selection resolves to a loaded product, or nothing")
    func selection() {
        viewModel.load()
        viewModel.selectedSKU = "B2"
        #expect(viewModel.selected?.name == "Beras Medium")
        viewModel.selectedSKU = "nope"
        #expect(viewModel.selected == nil)
    }
}
