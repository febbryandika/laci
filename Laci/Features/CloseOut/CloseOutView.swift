import Foundation
import LaciCore
import LaciMoney
import SwiftUI

/// The close-out (SPEC §3.3): one centred column, count first. The disclosure is disabled and has
/// no content until the view model holds a confirmed result, so the expected figure is unreachable
/// before the count, not merely hidden. A closed day shows its detail instead.
struct CloseOutView: View {
    private let dependencies: Dependencies
    @State private var viewModel: CloseOutViewModel
    @State private var payoutKind: PayoutKind = .supplier
    @State private var payoutAmount = ""
    @State private var payoutNote = ""
    @State private var cashRemoved = ""
    @State private var note = ""
    @State private var revealed = false

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: CloseOutViewModel(dependencies: dependencies))
    }

    var body: some View {
        Group {
            if viewModel.closeOut != nil {
                CloseOutDetailView(tradingDay: viewModel.targetDay, dependencies: dependencies)
            } else {
                form
            }
        }
        .navigationTitle("Tutup kas")
        .onAppear { viewModel.load() }
        .onDisappear { viewModel.clearError() }
        .onChange(of: viewModel.result) {
            if viewModel.result == nil {
                revealed = false
            }
        }
    }

    private var form: some View {
        Form {
            if viewModel.isPriorDay {
                priorDaySection
            }
            countSection
            payoutsSection
            revealSection
            if let error = viewModel.error {
                Section {
                    message(for: error).foregroundStyle(.red)
                }
            }
            saveSection
            latestSection
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var priorDaySection: some View {
        Section {
            Label(
                "Hari \(viewModel.targetDay.formatted(DateFormat.day)) belum ditutup",
                systemImage: "exclamationmark.triangle"
            )
        }
    }

    private var countSection: some View {
        Section {
            if viewModel.needsOpeningFloat {
                TextField("Modal awal", text: $viewModel.openingFloatText)
                    .keyboardType(.numberPad)
                    .disabled(viewModel.result != nil)
            }
            if let result = viewModel.result {
                amountRow("Uang tunai dihitung", result.counted)
                Button("Ubah hitungan") { viewModel.changeCount() }
            } else {
                TextField("Uang tunai dihitung", text: $viewModel.countedText)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("CloseOutView.counted")
                Button("Konfirmasi hitungan") { viewModel.enterCount() }
                    .disabled(viewModel.countedText.isEmpty)
                    .accessibilityIdentifier("CloseOutView.confirm")
            }
        } header: {
            Text("Hitung dulu")
        } footer: {
            Text("Hitung seluruh uang di laci sebelum melihat angka yang diharapkan.")
        }
    }

    private var payoutsSection: some View {
        Section {
            ForEach(viewModel.payouts, id: \.persistentModelID) { payout in
                PayoutRow(payout: payout)
            }
            .onDelete { offsets in
                for payout in offsets.map({ viewModel.payouts[$0] }) {
                    viewModel.deletePayout(payout)
                }
            }
            Picker("Jenis", selection: $payoutKind) {
                ForEach(PayoutKind.allCases, id: \.self) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            TextField("Jumlah", text: $payoutAmount)
                .keyboardType(.numberPad)
            TextField("Keterangan", text: $payoutNote)
            Button("Tambah pengeluaran") {
                viewModel.addPayout(kind: payoutKind, amountText: payoutAmount, note: payoutNote)
                if viewModel.error == nil {
                    payoutAmount = ""
                    payoutNote = ""
                }
            }
        } header: {
            Text("Pengeluaran kas")
        } footer: {
            if viewModel.result != nil {
                Text("Ubah hitungan untuk mengubah pengeluaran.")
            }
        }
        .disabled(viewModel.result != nil)
    }

    private var revealSection: some View {
        Section {
            DisclosureGroup("Perhitungan", isExpanded: $revealed) {
                if let inputs = viewModel.inputs, let result = viewModel.result {
                    amountRow("Modal awal", inputs.openingFloat)
                    amountRow("Penjualan tunai", inputs.cashSales)
                    amountRow("Retur tunai", inputs.cashRefunds)
                    amountRow("Pengeluaran", inputs.payouts)
                    amountRow("Kas seharusnya", result.expected).bold()
                    amountRow("Selisih", result.discrepancy)
                        .foregroundStyle(result.isShort ? .red : .primary)
                        .bold()
                }
            }
            .disabled(viewModel.result == nil)
            .accessibilityIdentifier("CloseOutView.reveal")
        }
    }

    private var saveSection: some View {
        Section {
            TextField("Setoran (uang diambil)", text: $cashRemoved)
                .keyboardType(.numberPad)
            TextField("Catatan", text: $note, axis: .vertical)
            Button("Simpan tutup kas") { viewModel.save(note: note, cashRemovedText: cashRemoved) }
                .disabled(viewModel.result == nil)
                .accessibilityIdentifier("CloseOutView.save")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Selisih lebih dari \(thresholdText) wajib diberi catatan.")
                Text("Setoran dicatat sebagai pengeluaran; modal awal besok adalah uang dihitung dikurangi setoran.")
            }
        }
    }

    @ViewBuilder
    private var latestSection: some View {
        if let latest = viewModel.latestClosed {
            Section {
                NavigationLink {
                    CloseOutDetailView(tradingDay: latest.tradingDay, dependencies: dependencies)
                        .navigationTitle(Text(latest.tradingDay, format: DateFormat.day))
                } label: {
                    LabeledContent("Tutup kas terakhir") {
                        Text(latest.tradingDay, format: DateFormat.day)
                    }
                }
            }
        }
    }

    private var thresholdText: Text {
        Text(ShopDefaults.discrepancyThreshold.amount, format: MoneyFormat.rupiah)
    }

    private func amountRow(_ label: LocalizedStringKey, _ amount: Money) -> some View {
        LabeledContent(label) {
            Text(amount.amount, format: MoneyFormat.rupiah).monospacedDigit()
        }
    }

    private func message(for error: CloseOutError) -> Text {
        switch error {
        case .countInvalid: Text("Jumlah hitungan tidak valid")
        case .openingFloatRequired: Text("Modal awal wajib diisi")
        case .amountInvalid: Text("Jumlah tidak valid")
        case .noteRequired: Text("Catatan wajib diisi")
        case .cashRemovedExceedsCount: Text("Setoran melebihi uang yang dihitung")
        case .countRequired: Text("Konfirmasi hitungan dulu")
        case .figuresChanged: Text("Ada transaksi baru setelah hitungan; hitung ulang")
        case .alreadyClosed: Text("Hari ini sudah ditutup")
        case .failed: Text("Gagal disimpan, coba lagi")
        }
    }
}

struct PayoutRow: View {
    let payout: Payout

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(payout.note)
                Text(payout.kind?.label ?? "?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(payout.amount, format: MoneyFormat.rupiah).monospacedDigit()
        }
    }
}

extension PayoutKind {
    var label: LocalizedStringKey {
        switch self {
        case .supplier: "Supplier"
        case .pettyCash: "Kas kecil"
        case .setoran: "Setoran"
        }
    }
}

#if DEBUG
    #Preview {
        if let dependencies = try? Dependencies.inMemory() {
            NavigationStack {
                CloseOutView(dependencies: dependencies)
            }
        } else {
            Text("In-memory store failed")
        }
    }
#endif
