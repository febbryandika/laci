import SwiftUI

/// The checkout sheet of the iPhone layout (SPEC §9); an iPad shows the same content in its own pane.
struct TenderView: View {
    let viewModel: SellViewModel
    let printer: PrinterCoordinator
    let focus: FocusState<SellField?>.Binding
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TenderContent(
                viewModel: viewModel, printer: printer, style: .sheet, focus: focus,
                presentPaywall: { dismiss() }, onNewSale: { dismiss() }
            )
            .navigationTitle("Bayar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("TenderView.cancel")
                }
            }
        }
    }
}
