import Foundation
import LaciCore
import Observation

/// The catalogue screen's state: the products, the search, and which one the inspector shows.
/// Read-only; a product is created through the new-product form and changed through an import.
@MainActor
@Observable
final class CatalogueViewModel {
    private(set) var products: [Product] = []
    private(set) var loadFailed = false
    var query = ""
    var selectedSKU: String?

    private let repository: any ProductRepository

    init(dependencies: Dependencies) {
        repository = dependencies.products
    }

    var results: [Product] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return products }
        return products.filter {
            $0.name.localizedCaseInsensitiveContains(needle) || $0.sku.localizedCaseInsensitiveContains(needle)
        }
    }

    var selected: Product? {
        products.first { $0.sku == selectedSKU }
    }

    func load() {
        do {
            products = try repository.all(includeArchived: false)
            loadFailed = false
        } catch {
            products = []
            loadFailed = true
        }
    }
}
