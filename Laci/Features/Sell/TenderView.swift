import Foundation
import LaciCore
import LaciMoney
import SwiftUI

/// Checkout: cash with quick-tender and change, or QRIS / transfer with a reference (SPEC §1, §8.3).
struct TenderView: View {
    enum Kind: Hashable, CaseIterable {
        case cash, qris, transfer
    }

    let viewModel: SellViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind = .cash
    @State private var customText = ""
    @State private var reference = ""
    @State private var completed: Sale?

    var body: some View {
        NavigationStack {
            Group {
                if let completed {
                    completedView(completed)
                } else {
                    tenderForm
                }
            }
            .navigationTitle("Bayar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
            }
            .onChange(of: kind) { viewModel.clearTenderError() }
            .onDisappear { viewModel.clearTenderError() }
        }
    }

    private var tenderForm: some View {
        Form {
            Picker("Metode", selection: $kind) {
                Text("Tunai").tag(Kind.cash)
                Text("QRIS").tag(Kind.qris)
                Text("Transfer").tag(Kind.transfer)
            }
            .pickerStyle(.segmented)

            switch kind {
            case .cash: cashSections
            case .qris: nonCashSections(.qris)
            case .transfer: nonCashSections(.transfer)
            }

            if let error = viewModel.tenderError {
                Section {
                    message(for: error)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("TenderView.error")
                }
            }
        }
    }

    // MARK: Cash

    private var tendered: Money? {
        DecimalInput.parse(customText).map(Money.init)
    }

    @ViewBuilder
    private var cashSections: some View {
        Section {
            LabeledContent("Total tunai") {
                Text(viewModel.cashTotal.amount, format: MoneyFormat.rupiah).bold()
            }
        }
        Section("Uang diterima") {
            // Tender keys are hit with a thumb at speed (SPEC §9), so each is at least 60pt square.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
                ForEach(viewModel.cashSuggestions, id: \.amount) { amount in
                    Button {
                        checkoutCash(amount)
                    } label: {
                        Text(amount.amount, format: MoneyFormat.rupiah)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .buttonStyle(.plain)
            TextField("Jumlah lain", text: $customText)
                .keyboardType(.numberPad)
            if let tendered {
                if let settlement = viewModel.settle(tendered: tendered) {
                    LabeledContent("Kembalian") {
                        Text(settlement.change.amount, format: MoneyFormat.rupiah).bold()
                    }
                } else {
                    Text("Uang kurang").foregroundStyle(.red)
                }
            }
        }
        Section {
            Button("Selesai") {
                if let tendered {
                    checkoutCash(tendered)
                }
            }
            .disabled(tendered == nil)
        }
    }

    private func checkoutCash(_ amount: Money) {
        viewModel.checkoutCash(tendered: amount)
        finishIfCommitted()
    }

    // MARK: Non-cash

    @ViewBuilder
    private func nonCashSections(_ method: NonCashMethod) -> some View {
        Section {
            LabeledContent("Total") {
                Text(viewModel.totals.grandTotal.amount, format: MoneyFormat.rupiah).bold()
            }
            TextField("Nomor referensi", text: $reference)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        }
        Section {
            Button("Selesai") {
                viewModel.checkoutNonCash(method, reference: reference)
                finishIfCommitted()
            }
        }
    }

    private func finishIfCommitted() {
        if viewModel.tenderError == nil, let sale = viewModel.lastSale {
            completed = sale
        }
    }

    // MARK: Completed

    private func completedView(_ sale: Sale) -> some View {
        Form {
            Section {
                LabeledContent("Penjualan") { Text("#\(sale.number)") }
                LabeledContent("Total") { Text(sale.total, format: MoneyFormat.rupiah) }
                if let change = sale.changeGiven {
                    LabeledContent("Kembalian") {
                        Text(change, format: MoneyFormat.rupiah).bold()
                    }
                }
                if let reference = sale.reference {
                    LabeledContent("Referensi") { Text(reference) }
                }
            }
            Section {
                Button("Penjualan baru") { dismiss() }
                    .accessibilityIdentifier("TenderView.newSale")
            }
        }
    }

    private func message(for error: TenderError) -> Text {
        switch error {
        case .emptyCart: Text("Keranjang kosong")
        case let .cashShort(rounded): Text("Uang kurang dari \(rounded.amount, format: MoneyFormat.rupiah)")
        case .missingReference: Text("Nomor referensi wajib diisi")
        case .commitFailed: Text("Penjualan gagal disimpan, coba lagi")
        }
    }
}
