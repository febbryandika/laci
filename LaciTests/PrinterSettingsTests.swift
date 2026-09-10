import Foundation
@testable import Laci
import LaciPrint
import Testing

@Suite("Printer settings")
struct PrinterSettingsTests {
    let defaults: UserDefaults

    init() throws {
        let suite = "PrinterSettingsTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("Nothing stored means no remembered printer and 58 mm paper")
    func empty() {
        #expect(PrinterSettings.remembered(in: defaults) == nil)
        #expect(PrinterSettings.paperWidth(in: defaults) == .mm58)
    }

    @Test("A remembered printer round-trips and can be forgotten")
    func rememberedRoundTrip() {
        let printer = RememberedPrinter(
            peripheralID: UUID(), serviceUUID: "49535343-FE7D-4AE5-8FA9-9FAFD205E455", name: "PT-210"
        )
        PrinterSettings.save(printer, in: defaults)
        #expect(PrinterSettings.remembered(in: defaults) == printer)
        PrinterSettings.forget(in: defaults)
        #expect(PrinterSettings.remembered(in: defaults) == nil)
    }

    @Test("A half-written pairing is treated as none rather than a printer with no service")
    func partialPairingIsNone() {
        defaults.set(UUID().uuidString, forKey: "printer.peripheralID")
        #expect(PrinterSettings.remembered(in: defaults) == nil)
    }

    @Test("Paper width round-trips and survives forgetting the printer")
    func paperWidthRoundTrip() {
        PrinterSettings.save(paperWidth: .mm80, in: defaults)
        PrinterSettings.forget(in: defaults)
        #expect(PrinterSettings.paperWidth(in: defaults) == .mm80)
    }
}
