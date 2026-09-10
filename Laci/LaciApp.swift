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
    let printer: PrinterCoordinator

    @MainActor
    private init(container: ModelContainer, transport: any PrinterTransporting) {
        self.container = container
        transactor = Transactor(container: container)
        products = SwiftDataProductRepository(transactor: transactor)
        sales = SwiftDataSaleRepository(transactor: transactor)
        stock = SwiftDataStockRepository(transactor: transactor)
        closeOuts = SwiftDataCloseOutRepository(transactor: transactor)
        printer = PrinterCoordinator(transport: transport, sales: sales, products: products)
    }

    /// The on-disk store. A POS that cannot open its store cannot sell, and there is nothing
    /// sensible to fall back to, so this stops the app with the reason in the crash log.
    @MainActor
    static func live() -> Dependencies {
        do {
            return try Dependencies(container: Store.container(), transport: PrinterTransport())
        } catch {
            fatalError("Laci cannot open its store: \(error)")
        }
    }

    /// A fresh in-memory store for previews and tests, with no printer unless a test supplies one.
    @MainActor
    static func inMemory(
        printer transport: any PrinterTransporting = UnavailablePrinterTransport()
    ) throws -> Dependencies {
        try Dependencies(container: Store.container(inMemory: true), transport: transport)
    }
}

@main
struct LaciApp: App {
    private let dependencies: Dependencies

    init() {
        dependencies = Dependencies.live()
        // SPEC §7.3: the shop switches the printer on at 7am and Laci is already connected at the
        // first sale, not after someone opens Settings.
        dependencies.printer.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
    }
}
