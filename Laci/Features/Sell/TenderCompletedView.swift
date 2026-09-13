import LaciCore
import SwiftUI

/// What a finished sale shows: the number, the change, and the receipt's fate (SPEC §7.3). Plain
/// rows in the same scroll view as the form, so the pane never swaps containers mid-checkout.
struct TenderCompletedView: View {
    let sale: Sale
    let printer: PrinterCoordinator
    let onNewSale: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabeledContent("Penjualan") { Text("#\(sale.number)") }
                .accessibilityIdentifier("Tender.completedNumber")
            LabeledContent("Total") { MoneyText(sale.total) }
            if let change = sale.changeGiven {
                LabeledContent("Kembalian") {
                    MoneyText(change).bold()
                        .accessibilityIdentifier("Tender.change")
                }
            }
            if let reference = sale.reference {
                LabeledContent("Referensi") { Text(reference) }
            }
            receiptRows
            Button {
                onNewSale()
            } label: {
                Text("Penjualan baru")
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("TenderView.newSale")
        }
    }

    /// Text only, never a spinner: a printer that is off must not hold up the next customer.
    @ViewBuilder
    private var receiptRows: some View {
        if printer.inFlightSaleID == sale.id {
            Text("Mencetak struk…").foregroundStyle(.secondary)
        } else if printer.failedSale?.id == sale.id {
            Label("Struk gagal dicetak", systemImage: "printer.slash")
            Button("Cetak ulang") { printer.reprint(saleID: sale.id) }
                .accessibilityIdentifier("TenderView.reprint")
        }
    }
}
