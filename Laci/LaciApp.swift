import LaciCore
import LaciMoney
import LaciPrint
import SwiftData
import SwiftUI

/// Composition root. Every dependency the app needs is built here, once, and handed down. View models
/// depend on the repository protocols, never on a `ModelContext`.
struct Dependencies {
    let container: ModelContainer
    let transactor: Transactor
    let products: any ProductRepository
    let sales: any SaleRepository
    let stock: any StockRepository
    let closeOuts: any CloseOutRepository

    @MainActor
    private init(container: ModelContainer) {
        self.container = container
        transactor = Transactor(container: container)
        products = SwiftDataProductRepository(transactor: transactor)
        sales = SwiftDataSaleRepository(transactor: transactor)
        stock = SwiftDataStockRepository(transactor: transactor)
        closeOuts = SwiftDataCloseOutRepository(transactor: transactor)
    }

    /// The on-disk store. A POS that cannot open its store cannot sell, and there is nothing
    /// sensible to fall back to, so this stops the app with the reason in the crash log.
    @MainActor
    static func live() -> Dependencies {
        do {
            return try Dependencies(container: Store.container())
        } catch {
            fatalError("Laci cannot open its store: \(error)")
        }
    }

    /// A fresh in-memory store for previews and tests.
    @MainActor
    static func inMemory() throws -> Dependencies {
        try Dependencies(container: Store.container(inMemory: true))
    }
}

@main
struct LaciApp: App {
    private let dependencies: Dependencies

    init() {
        dependencies = Dependencies.live()
    }

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
    }
}
