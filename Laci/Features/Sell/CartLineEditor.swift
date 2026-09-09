import Foundation
import LaciCore
import LaciMoney
import SwiftUI

/// Quantity, price override and one discount for a single cart line (SPEC §3.1.4). Reads the
/// live line from the view model each time so the row and the sheet never disagree.
struct CartLineEditor: View {
    let sku: String
    let viewModel: SellViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var quantityText: String
    @State private var priceText: String
    @State private var discount: DiscountDraft

    init(sku: String, viewModel: SellViewModel) {
        self.sku = sku
        self.viewModel = viewModel
        let line = viewModel.line(sku: sku)
        _quantityText = State(initialValue: line.map { $0.cart.quantity.formatted(MoneyFormat.plain) } ?? "")
        _priceText = State(initialValue: line.map { $0.cart.unitPrice.amount.formatted(MoneyFormat.plain) } ?? "")
        _discount = State(initialValue: DiscountDraft(line?.cart.discount ?? .none))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let line = viewModel.line(sku: sku) {
                    form(for: line)
                } else {
                    ContentUnavailableView("Baris sudah dihapus", systemImage: "cart.badge.minus")
                }
            }
            .navigationTitle("Ubah baris")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Selesai") { dismiss() }
                }
            }
        }
    }

    private func form(for line: SaleDraft.Line) -> some View {
        Form {
            Section {
                Text(line.cart.name)
                LabeledContent("Harga daftar") {
                    Text(line.listPrice.amount, format: MoneyFormat.rupiah)
                }
            }
            Section("Jumlah") {
                Stepper {
                    TextField("Jumlah", text: $quantityText)
                        .keyboardType(.decimalPad)
                } onIncrement: {
                    viewModel.increment(sku: sku)
                } onDecrement: {
                    viewModel.decrement(sku: sku)
                }
                .onChange(of: quantityText) {
                    if let quantity = DecimalInput.parse(quantityText) {
                        viewModel.setQuantity(sku: sku, quantity)
                    }
                }
                .onChange(of: line.cart.quantity) { _, quantity in
                    if DecimalInput.parse(quantityText) != quantity {
                        quantityText = quantity.formatted(MoneyFormat.plain)
                    }
                }
            }
            Section("Harga satuan") {
                TextField("Harga", text: $priceText)
                    .keyboardType(.numberPad)
                    .onChange(of: priceText) {
                        if let price = DecimalInput.parse(priceText) {
                            viewModel.setUnitPrice(sku: sku, Money(price))
                        }
                    }
            }
            Section("Diskon") {
                DiscountFields(draft: $discount)
                    .onChange(of: discount) { viewModel.setDiscount(sku: sku, discount.discount) }
                LabeledContent("Total baris") {
                    Text(viewModel.lineTotal(for: line).net.amount, format: MoneyFormat.rupiah)
                }
            }
            Section {
                Button("Hapus baris", role: .destructive) {
                    viewModel.remove(sku: sku)
                    dismiss()
                }
            }
        }
    }
}

/// The whole-sale discount, same editing state as a line.
struct SaleDiscountEditor: View {
    let viewModel: SellViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var discount: DiscountDraft

    init(viewModel: SellViewModel) {
        self.viewModel = viewModel
        _discount = State(initialValue: DiscountDraft(viewModel.saleDiscount))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Diskon penjualan") {
                    DiscountFields(draft: $discount)
                        .onChange(of: discount) { viewModel.setSaleDiscount(discount.discount) }
                }
                Section {
                    LabeledContent("Diskon") {
                        Text(viewModel.totals.saleDiscount.amount, format: MoneyFormat.rupiah)
                    }
                    LabeledContent("Total") {
                        Text(viewModel.totals.grandTotal.amount, format: MoneyFormat.rupiah)
                    }
                }
            }
            .navigationTitle("Diskon penjualan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Selesai") { dismiss() }
                }
            }
        }
    }
}
