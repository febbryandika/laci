import Foundation
import LaciCore
import SwiftData
import SwiftUI

/// One committed sale, read-only, with the two corrections SPEC §3.1.6 allows and a reprint
/// placeholder until the printer transport lands.
struct SaleDetailView: View {
    private let dependencies: Dependencies
    @State private var viewModel: SaleDetailViewModel
    @State private var voidReason = ""
    @State private var confirmingVoid = false
    @State private var confirmingRefund = false

    init(saleID: UUID, dependencies: Dependencies) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: SaleDetailViewModel(saleID: saleID, dependencies: dependencies))
    }

    var body: some View {
        Group {
            if let sale = viewModel.sale {
                form(for: sale)
            } else {
                ContentUnavailableView("Penjualan tidak ditemukan", systemImage: "questionmark")
            }
        }
        .navigationTitle(viewModel.sale.map { "#\($0.number)" } ?? "Penjualan")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Batalkan penjualan", isPresented: $confirmingVoid) {
            TextField("Alasan", text: $voidReason)
            Button("Batalkan penjualan", role: .destructive) { viewModel.void(reason: voidReason) }
            Button("Kembali", role: .cancel) {}
        } message: {
            Text("Stok dikembalikan. Penjualan tetap tercatat.")
        }
        .confirmationDialog("Retur seluruh penjualan?", isPresented: $confirmingRefund, titleVisibility: .visible) {
            Button("Retur", role: .destructive) { viewModel.refund() }
        }
        .onAppear { viewModel.load() }
        .onDisappear { viewModel.clearError() }
    }

    private func form(for sale: Sale) -> some View {
        Form {
            headerSection(sale)
            linesSection(sale)
            totalsSection(sale)
            paymentSection(sale)
            linksSection
            actionsSection
        }
    }

    private func headerSection(_ sale: Sale) -> some View {
        Section {
            LabeledContent("Waktu") { Text(sale.occurredAt, format: DateFormat.dateTime) }
            if let voidedAt = sale.voidedAt {
                LabeledContent("Dibatalkan") { Text(voidedAt, format: DateFormat.dateTime) }
                    .foregroundStyle(.red)
                LabeledContent("Alasan") { Text(sale.voidReason ?? "") }
            }
        }
    }

    private func linesSection(_ sale: Sale) -> some View {
        Section("Barang") {
            ForEach(sale.lines.sorted { $0.name < $1.name }, id: \.persistentModelID) { line in
                SaleLineRow(line: line)
            }
        }
    }

    private func totalsSection(_ sale: Sale) -> some View {
        Section {
            amountRow("Subtotal", sale.subtotal)
            if sale.discountTotal != 0 {
                amountRow("Diskon", sale.discountTotal)
            }
            if sale.taxTotal != 0 {
                amountRow("PPN", sale.taxTotal)
            }
            if sale.roundingDelta != 0 {
                amountRow("Pembulatan", sale.roundingDelta)
            }
            amountRow("Total", sale.total).bold()
        }
    }

    private func paymentSection(_ sale: Sale) -> some View {
        Section {
            LabeledContent("Metode") { Text(sale.paymentLabel) }
            if let tendered = sale.amountTendered {
                amountRow("Uang diterima", tendered)
            }
            if let change = sale.changeGiven {
                amountRow("Kembalian", change)
            }
            if let reference = sale.reference {
                LabeledContent("Referensi") { Text(reference) }
            }
        }
    }

    @ViewBuilder
    private var linksSection: some View {
        if viewModel.refundedSale != nil || !viewModel.refunds.isEmpty {
            Section {
                if let original = viewModel.refundedSale {
                    NavigationLink("Retur dari #\(original.number)") {
                        SaleDetailView(saleID: original.id, dependencies: dependencies)
                    }
                }
                ForEach(viewModel.refunds, id: \.id) { refund in
                    NavigationLink("Diretur di #\(refund.number)") {
                        SaleDetailView(saleID: refund.id, dependencies: dependencies)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        if let error = viewModel.error {
            Section {
                message(for: error).foregroundStyle(.red)
            }
        }
        if viewModel.canVoid || viewModel.canRefund {
            Section {
                if viewModel.canRefund {
                    Button("Retur") { confirmingRefund = true }
                }
                if viewModel.canVoid {
                    Button("Batalkan penjualan", role: .destructive) {
                        voidReason = ""
                        confirmingVoid = true
                    }
                }
            }
        }
        Section {
            Button("Cetak ulang") {}
                .disabled(true)
        } footer: {
            Text("Printer belum disiapkan")
        }
    }

    private func amountRow(_ label: LocalizedStringKey, _ amount: Decimal) -> some View {
        LabeledContent(label) {
            Text(amount, format: MoneyFormat.rupiah).monospacedDigit()
        }
    }

    private func message(for error: CorrectionError) -> Text {
        switch error {
        case .reasonRequired: Text("Alasan wajib diisi")
        case .alreadyVoided: Text("Penjualan sudah dibatalkan")
        case .hasRefund: Text("Penjualan sudah diretur")
        case .isRefund: Text("Retur tidak bisa diretur lagi; batalkan retur ini")
        case .failed: Text("Gagal disimpan, coba lagi")
        }
    }
}

private struct SaleLineRow: View {
    let line: SaleLine

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.name)
                HStack(spacing: 4) {
                    Text(line.quantity, format: MoneyFormat.plain)
                    Text("×")
                    Text(line.unitPrice, format: MoneyFormat.rupiah)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if line.discountAmount != 0 {
                    HStack(spacing: 4) {
                        Text("Diskon")
                        Text(line.discountAmount, format: MoneyFormat.rupiah)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(line.lineTotal, format: MoneyFormat.rupiah).monospacedDigit()
        }
    }
}

#if DEBUG
    #Preview {
        if let dependencies = try? Dependencies.inMemory() {
            NavigationStack {
                SaleDetailView(saleID: UUID(), dependencies: dependencies)
            }
        } else {
            Text("In-memory store failed")
        }
    }
#endif
