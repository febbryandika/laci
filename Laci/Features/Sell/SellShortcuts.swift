import LaciCore
import SwiftUI

/// The ⌘ shortcuts of SPEC §9, on real buttons so every one is listed in the ⌘-hold overlay and
/// none is a hidden gesture. Zero-sized and transparent, never `.hidden()`: a hidden view gives up
/// its key commands. ⌘L lives on the visible "Tutup kas" toolbar button; the bare keys (↑ ↓ + −)
/// belong to the cart list and act only while it has focus.
struct SellShortcuts: View {
    let viewModel: SellViewModel
    let printer: PrinterCoordinator
    let focusSearch: () -> Void
    let checkoutExactCash: () -> Void
    let openTender: () -> Void
    let escape: () -> Void

    var body: some View {
        Group {
            Button("Cari produk", action: focusSearch)
                .keyboardShortcut("k")
            Button("Bayar tunai pas", action: checkoutExactCash)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(viewModel.lines.isEmpty)
            Button("Buka pembayaran", action: openTender)
                .keyboardShortcut(.return, modifiers: [.command, .shift])
            Button("Hapus baris terpilih") { viewModel.removeSelected() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(viewModel.selectedSKU == nil)
            Button("Cetak ulang struk terakhir") {
                if let sale = viewModel.lastSale {
                    printer.reprint(saleID: sale.id)
                }
            }
            .keyboardShortcut("p")
            .disabled(viewModel.lastSale == nil)
            Button("Batal", action: escape)
                .keyboardShortcut(.cancelAction)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}
