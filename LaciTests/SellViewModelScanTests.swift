import Foundation
@testable import Laci
import LaciCore
import LaciMoney
import Testing

private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
/// Valid EAN-13s (see LaciCoreTests) and one with a wrong check digit.
private let owned = "5901234123457"
private let unknownEAN = "8992761111083"
private let misread = "5901234123458"

@MainActor
@Suite("Sell view model: scanning")
struct SellViewModelScanTests {
    let dependencies: Dependencies
    let viewModel: SellViewModel

    init() throws {
        dependencies = try Dependencies.inMemory()
        viewModel = SellViewModel(dependencies: dependencies, now: { fixedNow })
        let product = Product(
            sku: "A", name: "Item A", unit: "pcs", cost: 0, price: 12350, tracksStock: true, stockOnHand: 10,
            updatedAt: fixedNow
        )
        try dependencies.products.create(product)
        try dependencies.products.addBarcode(owned, symbology: .ean13, to: "A")
        viewModel.loadCatalogue()
    }

    @Test("A known barcode adds the product, and again increments the same line")
    func knownBarcode() {
        viewModel.didRead(code: owned, symbology: .ean13)
        viewModel.didRead(code: owned, symbology: .ean13)
        #expect(viewModel.lines.map(\.cart.sku) == ["A"])
        #expect(viewModel.lines.first?.cart.quantity == 2)
        #expect(viewModel.scansAccepted == 2)
        #expect(viewModel.scanNotice == nil)
        #expect(viewModel.pendingBarcode == nil)
    }

    @Test("A bad checksum says scan again and touches nothing else")
    func badChecksum() {
        viewModel.didRead(code: misread, symbology: .ean13)
        #expect(viewModel.scanNotice == .scanAgain)
        #expect(viewModel.lines.isEmpty)
        #expect(viewModel.scansAccepted == 0)
        #expect(viewModel.pendingBarcode == nil)
    }

    @Test("A successful scan clears an earlier notice")
    func noticeCleared() {
        viewModel.didRead(code: misread, symbology: nil)
        viewModel.didRead(code: owned, symbology: nil)
        #expect(viewModel.scanNotice == nil)
    }

    @Test("An unknown valid EAN becomes a pending barcode typed by its shape")
    func unknownEANPending() {
        viewModel.didRead(code: unknownEAN, symbology: nil)
        #expect(viewModel.pendingBarcode == PendingBarcode(value: unknownEAN, symbology: .ean13))
        #expect(viewModel.lines.isEmpty)
        #expect(viewModel.scanNotice == nil)
    }

    @Test("A wedge payload that is not an EAN is recorded as Code 128; a camera type wins over the shape")
    func symbologyResolution() {
        viewModel.didRead(code: "ABC-99", symbology: nil)
        #expect(viewModel.pendingBarcode?.symbology == .code128)
        viewModel.didRead(code: "ABC-98", symbology: .code39)
        #expect(viewModel.pendingBarcode?.symbology == .code39)
    }

    @Test("The wedge's trailing return and stray whitespace are trimmed; an empty payload is ignored")
    func trimming() {
        viewModel.didRead(code: "  \(owned)\r\n", symbology: nil)
        #expect(viewModel.lines.count == 1)
        viewModel.didRead(code: " \r\n", symbology: nil)
        #expect(viewModel.lines.count == 1)
        #expect(viewModel.scanNotice == nil)
    }

    @Test("Deleting a line resets the debouncer, so the same code scans again at once")
    func deleteThenRescan() {
        #expect(viewModel.scanDebouncer.shouldAccept(owned))
        viewModel.didRead(code: owned, symbology: .ean13)
        #expect(!viewModel.scanDebouncer.shouldAccept(owned))
        viewModel.remove(sku: "A")
        #expect(viewModel.lines.isEmpty)
        #expect(viewModel.scanDebouncer.shouldAccept(owned))
        viewModel.didRead(code: owned, symbology: .ean13)
        #expect(viewModel.lines.map(\.cart.quantity) == [1])
    }

    @Test("The pending barcode can be cleared without side effects")
    func clearPending() {
        viewModel.didRead(code: unknownEAN, symbology: nil)
        viewModel.clearPendingBarcode()
        #expect(viewModel.pendingBarcode == nil)
        #expect(viewModel.lines.isEmpty)
    }
}
