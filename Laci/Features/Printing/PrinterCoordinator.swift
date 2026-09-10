import Foundation
import LaciCore
import LaciPrint
import Observation
import os

/// Everything the screens know about the printer. Printing is a detached task that nothing awaits:
/// checkout commits the sale, clears the cart, then hands the sale here and moves on (SPEC §7.3).
/// A failure becomes a banner and a mark on the sale, never a dialog, a retry loop or a spinner.
@MainActor
@Observable
final class PrinterCoordinator {
    private(set) var connection: PrinterConnection = .disconnected
    private(set) var paperWidth: PaperWidth
    private(set) var remembered: RememberedPrinter?
    private(set) var lastOutcome: PrintOutcome?
    private(set) var lastDuration: Duration?
    /// The sale whose struk is being printed right now; the completed view says "Mencetak…" for it.
    private(set) var inFlightSaleID: UUID?
    /// The non-blocking banner (SPEC §9 states). Cleared by a successful reprint or by the cashier.
    private(set) var failedSale: FailedSale?

    private let transport: any PrinterTransporting
    private let sales: any SaleRepository
    private let products: any ProductRepository
    private let defaults: UserDefaults
    private let now: () -> Date
    private let clock = ContinuousClock()
    private let log = Logger(subsystem: "id.laci", category: "print")
    private var connectionTask: Task<Void, Never>?

    init(
        transport: any PrinterTransporting, sales: any SaleRepository, products: any ProductRepository,
        defaults: UserDefaults = .standard, now: @escaping () -> Date = { Date() }
    ) {
        self.transport = transport
        self.sales = sales
        self.products = products
        self.defaults = defaults
        self.now = now
        paperWidth = PrinterSettings.paperWidth(in: defaults)
        remembered = PrinterSettings.remembered(in: defaults)
    }

    var negotiatedMTU: Int? {
        if case let .connected(_, mtu) = connection { mtu } else { nil }
    }

    var isConnected: Bool {
        if case .connected = connection { true } else { false }
    }

    /// Launch: the transport starts reconnecting to the remembered printer, and its state flows here.
    func start() {
        guard connectionTask == nil else { return }
        let transport = transport
        connectionTask = Task { [weak self] in
            await transport.start()
            for await state in transport.connection {
                guard let self else { return }
                connection = state
            }
        }
    }

    // MARK: Printing

    /// Returns before a byte is written. The caller must already have committed the sale and
    /// cleared the cart; this is the single most important ordering in the app (SPEC §7.3).
    func printReceipt(for sale: Sale) {
        inFlightSaleID = sale.id
        let receipt = ReceiptFactory.make(sale, products: products, isReprint: false)
        run(receipt: receipt, sale: FailedSale(id: sale.id, number: sale.number))
    }

    func reprint(saleID: UUID) {
        guard let sale = try? sales.sale(id: saleID) else {
            record(.failed(.saleNotFound), duration: nil, sale: nil)
            return
        }
        inFlightSaleID = sale.id
        let receipt = ReceiptFactory.make(sale, products: products, isReprint: true)
        run(receipt: receipt, sale: FailedSale(id: sale.id, number: sale.number))
    }

    func printTest() {
        send(DiagnosticReceipt.render(paper: paperWidth), sale: nil)
    }

    func dismissFailure() {
        failedSale = nil
    }

    private func run(receipt: Receipt, sale: FailedSale) {
        let paper = paperWidth
        // Rendering is pure and off the main actor, like the write that follows.
        Task.detached { [self] in
            let data = ReceiptRenderer.render(receipt, paper: paper)
            await send(data, sale: sale)
        }
    }

    private func send(_ data: Data, sale: FailedSale?) {
        let transport = transport
        let clock = clock
        Task.detached { [self] in
            let start = clock.now
            let outcome: PrintOutcome
            do {
                try await transport.send(data)
                outcome = .printed
            } catch let error as PrintError {
                outcome = .failed(error)
            } catch {
                outcome = .failed(.transport(String(describing: error)))
            }
            await record(outcome, duration: start.duration(to: clock.now), sale: sale)
        }
    }

    private func record(_ outcome: PrintOutcome, duration: Duration?, sale: FailedSale?) {
        lastOutcome = outcome
        lastDuration = duration
        if inFlightSaleID == sale?.id {
            inFlightSaleID = nil
        }
        switch outcome {
        case .printed:
            log.info("print ok in \(duration.map { "\($0)" } ?? "-", privacy: .public)")
            guard let sale else { return }
            if failedSale?.id == sale.id {
                failedSale = nil
            }
            if (try? sales.sale(id: sale.id))?.receiptFailedAt != nil {
                try? sales.markReceipt(saleID: sale.id, failedAt: nil)
            }
        case let .failed(error):
            log.error("print failed: \(String(describing: error), privacy: .public)")
            guard let sale else { return }
            failedSale = sale
            try? sales.markReceipt(saleID: sale.id, failedAt: now())
        }
    }

    // MARK: Pairing

    func scan() -> AsyncStream<DiscoveredPrinter> {
        transport.scan()
    }

    func stopScan() async {
        await transport.stopScan()
    }

    func pair(_ printer: DiscoveredPrinter) async throws {
        let service = try await transport.connect(printer.id)
        let paired = RememberedPrinter(peripheralID: printer.id, serviceUUID: service, name: printer.name)
        PrinterSettings.save(paired, in: defaults)
        remembered = paired
    }

    func forget() async {
        await transport.disconnect()
        PrinterSettings.forget(in: defaults)
        remembered = nil
    }

    func setPaperWidth(_ width: PaperWidth) {
        paperWidth = width
        PrinterSettings.save(paperWidth: width, in: defaults)
    }
}
