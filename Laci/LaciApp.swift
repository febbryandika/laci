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
        self.init(container: container) { sales, products in
            PrinterCoordinator(transport: transport, sales: sales, products: products)
        }
    }

    @MainActor
    private init(
        container: ModelContainer,
        printer: (_ sales: any SaleRepository, _ products: any ProductRepository) -> PrinterCoordinator
    ) {
        self.container = container
        transactor = Transactor(container: container)
        products = SwiftDataProductRepository(transactor: transactor)
        sales = SwiftDataSaleRepository(transactor: transactor)
        stock = SwiftDataStockRepository(transactor: transactor)
        closeOuts = SwiftDataCloseOutRepository(transactor: transactor)
        self.printer = printer(sales, products)
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

    /// A store at any path, for the restore tests; the app itself uses `Store.storeURL`.
    @MainActor
    static func onDisk(
        at url: URL, printer transport: any PrinterTransporting = UnavailablePrinterTransport()
    ) throws -> Dependencies {
        try Dependencies(container: Store.container(at: url), transport: transport)
    }

    /// After a restore: the store at `url` opened afresh, every repository rebuilt on it, and the
    /// printer coordinator kept and rebound rather than rebuilt (SPEC §7.3: one central, one
    /// connection stream).
    @MainActor
    static func reopened(at url: URL, keeping printer: PrinterCoordinator) throws -> Dependencies {
        try Dependencies(container: Store.container(at: url)) { sales, products in
            printer.rebind(sales: sales, products: products)
            return printer
        }
    }
}

@main
struct LaciApp: App {
    @State private var session: AppSession
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let session = AppSession.live()
        // SPEC §7.3: the shop switches the printer on at 7am and Laci is already connected at the
        // first sale, not after someone opens Settings.
        session.dependencies.printer.start()
        // SPEC §5.3: the charging-time backup. Registration must precede the end of launch.
        BackupScheduler.register(service: session.backups)
        session.backups.onAutomaticChanged = { BackupScheduler.schedule(enabled: $0) }
        _session = State(initialValue: session)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .onChange(of: scenePhase) {
                    if scenePhase == .background {
                        BackupScheduler.schedule(enabled: session.backups.automaticEnabled)
                    }
                }
        }
    }
}
