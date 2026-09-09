import Foundation
import LaciCore
import SwiftUI

/// A saved close-out, read straight from the row: `discrepancy` is the published number (SPEC §10)
/// and is never recomputed here. The attribution picker is the one editable field.
struct CloseOutDetailView: View {
    @State private var viewModel: CloseOutDetailViewModel

    init(tradingDay: Date, dependencies: Dependencies) {
        _viewModel = State(initialValue: CloseOutDetailViewModel(tradingDay: tradingDay, dependencies: dependencies))
    }

    var body: some View {
        Group {
            if let closeOut = viewModel.closeOut {
                form(for: closeOut)
            } else {
                ContentUnavailableView("Tutup kas tidak ditemukan", systemImage: "questionmark")
            }
        }
        .onAppear { viewModel.load() }
    }

    private func form(for closeOut: CloseOut) -> some View {
        Form {
            Section {
                LabeledContent("Hari") { Text(closeOut.tradingDay, format: DateFormat.day) }
                LabeledContent("Ditutup") { Text(closeOut.closedAt, format: DateFormat.dateTime) }
            }
            Section("Perhitungan") {
                amountRow("Modal awal", closeOut.openingFloat)
                amountRow("Penjualan tunai", closeOut.cashSales)
                amountRow("Retur tunai", closeOut.cashRefunds)
                amountRow("Pengeluaran", closeOut.payouts)
                amountRow("Kas seharusnya", closeOut.expectedDrawer)
                amountRow("Uang dihitung", closeOut.countedDrawer)
                amountRow("Selisih", closeOut.discrepancy)
                    .foregroundStyle(closeOut.discrepancy < 0 ? .red : .primary)
                    .bold()
            }
            if let note = closeOut.note {
                Section("Catatan") { Text(note) }
            }
            Section {
                Picker("Atribusi", selection: attribution) {
                    Text("Belum ditentukan").tag(Attribution?.none)
                    ForEach(Attribution.allCases, id: \.self) { kind in
                        Text(kind.label).tag(Optional(kind))
                    }
                }
                .accessibilityIdentifier("CloseOutDetailView.attribution")
                if viewModel.failed {
                    Text("Gagal disimpan, coba lagi").foregroundStyle(.red)
                }
            } footer: {
                Text("Selisih ditelusuri saat itu juga: kesalahan operator, bug Laci, atau belum jelas.")
            }
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var attribution: Binding<Attribution?> {
        Binding(
            get: { viewModel.closeOut?.attributionKind },
            set: { viewModel.setAttribution($0) }
        )
    }

    private func amountRow(_ label: LocalizedStringKey, _ amount: Decimal) -> some View {
        LabeledContent(label) {
            Text(amount, format: MoneyFormat.rupiah).monospacedDigit()
        }
    }
}

extension Attribution {
    var label: LocalizedStringKey {
        switch self {
        case .operatorError: "Operator"
        case .bug: "Bug"
        case .unresolved: "Belum jelas"
        }
    }
}

#if DEBUG
    #Preview {
        if let dependencies = try? Dependencies.inMemory() {
            NavigationStack {
                CloseOutDetailView(tradingDay: Date(), dependencies: dependencies)
            }
        } else {
            Text("In-memory store failed")
        }
    }
#endif
