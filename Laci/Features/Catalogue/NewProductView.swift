import LaciCore
import SwiftUI

/// The form an unknown barcode opens (SPEC §3.1.2). The barcode is shown, not edited: it is what
/// the camera read, and the form exists to attach a product to it.
struct NewProductView: View {
    let onCreated: (Product) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: NewProductViewModel

    init(pending: PendingBarcode, dependencies: Dependencies, onCreated: @escaping (Product) -> Void) {
        self.onCreated = onCreated
        _viewModel = State(initialValue: NewProductViewModel(barcode: pending, dependencies: dependencies))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Barcode") {
                        Text(viewModel.barcode.value).monospacedDigit()
                    }
                }
                Section("Produk") {
                    TextField("SKU", text: $viewModel.sku)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("NewProductView.sku")
                    TextField("Nama", text: $viewModel.name)
                        .accessibilityIdentifier("NewProductView.name")
                    TextField("Satuan", text: $viewModel.unit)
                        .textInputAutocapitalization(.never)
                }
                Section("Harga") {
                    TextField("Harga jual", text: $viewModel.priceText)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("NewProductView.price")
                    TextField("Modal", text: $viewModel.costText)
                        .keyboardType(.numberPad)
                }
                Section("Stok") {
                    Toggle("Lacak stok", isOn: $viewModel.tracksStock)
                    if viewModel.tracksStock {
                        TextField("Stok awal", text: $viewModel.stockText)
                            .keyboardType(.decimalPad)
                    }
                }
                if let error = viewModel.error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("NewProductView.error")
                    }
                }
            }
            .navigationTitle("Produk baru")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") {
                        if let product = viewModel.save() {
                            onCreated(product)
                        }
                    }
                    .accessibilityIdentifier("NewProductView.save")
                }
            }
        }
    }
}
