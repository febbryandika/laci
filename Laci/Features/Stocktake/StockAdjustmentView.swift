import LaciCore
import SwiftUI

/// Manual stock in and waste with a reason and a note (SPEC §3.2, §4). Pushed from the stocktake
/// screen; each save is one movement.
struct StockAdjustmentView: View {
    @State private var viewModel: StockAdjustmentViewModel

    init(dependencies: Dependencies) {
        _viewModel = State(initialValue: StockAdjustmentViewModel(dependencies: dependencies))
    }

    var body: some View {
        Form {
            Section("Produk") {
                HStack {
                    TextField("SKU atau barcode", text: $viewModel.skuText)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { viewModel.lookup() }
                        .accessibilityIdentifier("StockAdjustmentView.sku")
                    Button("Cari") { viewModel.lookup() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("StockAdjustmentView.lookup")
                }
                if let product = viewModel.product {
                    LabeledContent(product.name) {
                        Text("stok \(product.stockOnHand.formatted(MoneyFormat.plain)) \(product.unit)")
                            .monospacedDigit()
                    }
                    .accessibilityIdentifier("StockAdjustmentView.product")
                }
            }
            Section("Penyesuaian") {
                Picker("Jenis", selection: $viewModel.kind) {
                    Text("Stok masuk").tag(AdjustmentKind.stockIn)
                    Text("Rusak / hilang").tag(AdjustmentKind.waste)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("StockAdjustmentView.kind")
                TextField("Jumlah", text: $viewModel.quantityText)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("StockAdjustmentView.quantity")
                TextField("Catatan", text: $viewModel.note)
                    .accessibilityIdentifier("StockAdjustmentView.note")
            }
            Section {
                Button("Simpan") { viewModel.save() }
                    .disabled(viewModel.product == nil)
                    .accessibilityIdentifier("StockAdjustmentView.save")
                if let saved = viewModel.saved {
                    let delta = saved.delta.formatted(MoneyFormat.plain.sign(strategy: .always()))
                    Text("Tersimpan: \(saved.sku) \(delta)")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("StockAdjustmentView.saved")
                }
                if let error = viewModel.error {
                    message(for: error)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("StockAdjustmentView.error")
                }
            }
        }
        .navigationTitle("Penyesuaian stok")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func message(for error: StockAdjustmentError) -> Text {
        switch error {
        case .productNotFound: Text("Produk tidak ditemukan")
        case .untracked: Text("Produk ini tidak melacak stok")
        case .quantityInvalid: Text("Jumlah harus lebih dari nol")
        case .failed: Text("Gagal menyimpan penyesuaian, coba lagi")
        }
    }
}
