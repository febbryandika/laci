import Foundation
@testable import Laci
import LaciCore
import LaciMoney
import LaciPrint
import Testing

private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

/// The print pipeline around a fake transport: what checkout, reprint and the test print record.
@MainActor
struct PrinterFixture {
    let transport: FakePrinterTransport
    let dependencies: Dependencies
    let printer: PrinterCoordinator
    let defaults: UserDefaults

    init(mode: FakePrinterTransport.Mode, discoverable: [DiscoveredPrinter] = []) throws {
        transport = FakePrinterTransport(mode: mode, discoverable: discoverable)
        dependencies = try Dependencies.inMemory(printer: transport)
        let suite = "PrinterCoordinatorTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        printer = PrinterCoordinator(
            transport: transport, sales: dependencies.sales, products: dependencies.products,
            defaults: defaults, now: { fixedNow }
        )
        try dependencies.products.create(Product(
            sku: "A", name: "Item A", unit: "pcs", cost: 0, price: 12350, tracksStock: false, updatedAt: fixedNow
        ))
    }

    func sale() throws -> Sale {
        let cart = CartLine(
            sku: "A", name: "Item A", quantity: 1, unitPrice: Money(12350), discount: .none, taxable: true
        )
        let totals = Pricing.totals(lines: [cart], saleDiscount: .none, tax: .nonPKP)
        let settlement = try #require(Tender.settle(total: totals.grandTotal, tendered: Money(20000)))
        let draft = SaleDraft(
            lines: [SaleDraft.Line(cart: cart, listPrice: Money(12350))], totals: totals, payment: .cash(settlement),
            occurredAt: fixedNow
        )
        return try dependencies.sales.commit(
            draft, tradingDay: ShopDefaults.tradingDay, timeZone: ShopDefaults.timeZone
        )
    }
}

/// CP437 bytes of an ASCII string, for looking inside a payload.
private func bytes(_ text: String) -> Data {
    Data(text.utf8)
}

@MainActor
@Suite("Printer coordinator")
struct PrinterCoordinatorTests {
    @Test("A successful print records the outcome and its duration and leaves the sale clean")
    func success() async throws {
        let fixture = try PrinterFixture(mode: .succeed)
        let sale = try fixture.sale()
        fixture.printer.printReceipt(for: sale)
        #expect(fixture.printer.inFlightSaleID == sale.id)
        #expect(await until { fixture.printer.lastOutcome == .printed })
        #expect(fixture.printer.lastDuration != nil)
        #expect(fixture.printer.inFlightSaleID == nil)
        #expect(fixture.printer.failedSale == nil)
        #expect(sale.receiptFailedAt == nil)
        #expect(fixture.transport.payloads.count == 1)
        #expect(fixture.transport.payloads[0].range(of: bytes("No. \(sale.number)")) != nil)
        #expect(fixture.transport.payloads[0].range(of: bytes("*** CETAK ULANG ***")) == nil)
    }

    @Test("A failed print marks the sale, raises the banner, and never throws at the caller")
    func failure() async throws {
        let fixture = try PrinterFixture(mode: .fail(.notConnected))
        let sale = try fixture.sale()
        fixture.printer.printReceipt(for: sale)
        #expect(await until { fixture.printer.lastOutcome == .failed(.notConnected) })
        #expect(fixture.printer.failedSale == FailedSale(id: sale.id, number: sale.number))
        #expect(fixture.printer.inFlightSaleID == nil)
        let stored = try fixture.dependencies.sales.sale(id: sale.id)
        #expect(stored?.receiptFailedAt == fixedNow)
    }

    @Test("A reprint is marked as one and a success clears the failure on the sale")
    func reprintClearsFailure() async throws {
        let fixture = try PrinterFixture(mode: .succeed)
        let sale = try fixture.sale()
        try fixture.dependencies.sales.markReceipt(saleID: sale.id, failedAt: fixedNow)
        fixture.printer.reprint(saleID: sale.id)
        #expect(await until { fixture.printer.lastOutcome == .printed })
        let stored = try fixture.dependencies.sales.sale(id: sale.id)
        #expect(stored?.receiptFailedAt == nil)
        #expect(fixture.transport.payloads.last?.range(of: bytes("*** CETAK ULANG ***")) != nil)
    }

    @Test("A reprint of an unknown sale fails quietly")
    func reprintUnknown() async throws {
        let fixture = try PrinterFixture(mode: .succeed)
        fixture.printer.reprint(saleID: UUID())
        #expect(await until { fixture.printer.lastOutcome != nil })
        #expect(fixture.printer.lastOutcome == .failed(.saleNotFound))
        #expect(fixture.transport.payloads.isEmpty)
    }

    @Test("Dismissing the banner does not touch the sale")
    func dismiss() async throws {
        let fixture = try PrinterFixture(mode: .fail(.paperOut))
        let sale = try fixture.sale()
        fixture.printer.printReceipt(for: sale)
        #expect(await until { fixture.printer.failedSale != nil })
        fixture.printer.dismissFailure()
        #expect(fixture.printer.failedSale == nil)
        let stored = try fixture.dependencies.sales.sale(id: sale.id)
        #expect(stored?.receiptFailedAt == fixedNow)
    }

    @Test("The test print sends the diagnostic receipt at the chosen paper width")
    func diagnosticPrint() async throws {
        let fixture = try PrinterFixture(mode: .succeed)
        fixture.printer.setPaperWidth(.mm80)
        fixture.printer.printTest()
        #expect(await until { fixture.printer.lastOutcome == .printed })
        #expect(fixture.transport.payloads == [DiagnosticReceipt.render(paper: .mm80)])
        #expect(PrinterSettings.paperWidth(in: fixture.defaults) == .mm80)
    }

    @Test("A hanging printer leaves the print in flight and the caller free")
    func hang() async throws {
        let fixture = try PrinterFixture(mode: .hang)
        let sale = try fixture.sale()
        fixture.printer.printReceipt(for: sale)
        #expect(fixture.printer.inFlightSaleID == sale.id)
        #expect(await until(.milliseconds(100)) { fixture.printer.lastOutcome != nil } == false)
        #expect(fixture.printer.lastOutcome == nil)
    }

    @Test("Pairing remembers the printer and the connection stream drives the state")
    func pairing() async throws {
        let found = DiscoveredPrinter(id: UUID(), name: "PT-210")
        let fixture = try PrinterFixture(mode: .succeed, discoverable: [found])
        fixture.printer.start()
        #expect(await until { fixture.printer.connection == .connected(name: "Fake", mtu: 20) })
        #expect(fixture.printer.negotiatedMTU == 20)

        var seen: [DiscoveredPrinter] = []
        for await printer in fixture.printer.scan() {
            seen.append(printer)
        }
        #expect(seen == [found])

        try await fixture.printer.pair(found)
        #expect(fixture.transport.connected == [found.id])
        #expect(fixture.printer.remembered == RememberedPrinter(
            peripheralID: found.id, serviceUUID: "FF00", name: "PT-210"
        ))
        #expect(PrinterSettings.remembered(in: fixture.defaults)?.name == "PT-210")

        await fixture.printer.forget()
        #expect(fixture.transport.forgotten)
        #expect(fixture.printer.remembered == nil)
        #expect(PrinterSettings.remembered(in: fixture.defaults) == nil)
    }
}
