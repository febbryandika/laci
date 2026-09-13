import LaciCore
import SwiftUI

/// What a finished sale shows: the number, the change, and the receipt's fate (SPEC §7.3).
struct TenderCompletedView: View {
    let sale: Sale
    let printer: PrinterCoordinator
    let onNewSale: () -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("Penjualan") { Text("#\(sale.number)") }
                LabeledContent("Total") { MoneyText(sale.total) }
                if let change = sale.changeGiven {
                    LabeledContent("Kembalian") {
                        MoneyText(change).bold()
                    }
                    .accessibilityIdentifier("Tender.change")
                }
                if let reference = sale.reference {
                    LabeledContent("Referensi") { Text(reference) }
                }
            }
            receiptSection
            Section {
                Button("Penjualan baru", action: onNewSale)
                    .accessibilityIdentifier("TenderView.newSale")
            }
        }
    }

    /// Text only, never a spinner: a printer that is off must not hold up the next customer.
    @ViewBuilder
    private var receiptSection: some View {
        if printer.inFlightSaleID == sale.id {
            Section {
                Text("Mencetak struk…").foregroundStyle(.secondary)
            }
        } else if printer.failedSale?.id == sale.id {
            Section {
                Label("Struk gagal dicetak", systemImage: "printer.slash")
                Button("Cetak ulang") { printer.reprint(saleID: sale.id) }
                    .accessibilityIdentifier("TenderView.reprint")
            }
        }
    }
}
