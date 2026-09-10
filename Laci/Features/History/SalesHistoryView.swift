import Foundation
import LaciCore
import SwiftUI

/// Past sales, newest first, searchable by number. A plain list; the three-pane layout is later.
struct SalesHistoryView: View {
    private let dependencies: Dependencies
    @State private var viewModel: SalesHistoryViewModel

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: SalesHistoryViewModel(dependencies: dependencies))
    }

    var body: some View {
        List(viewModel.sales, id: \.id) { sale in
            NavigationLink {
                SaleDetailView(saleID: sale.id, dependencies: dependencies)
            } label: {
                SaleRow(sale: sale)
            }
            .onAppear {
                if sale.id == viewModel.sales.last?.id {
                    viewModel.loadMore()
                }
            }
        }
        .accessibilityIdentifier("SalesHistoryView.list")
        .overlay { placeholder }
        .navigationTitle("Riwayat")
        .searchable(text: $viewModel.query, prompt: "Nomor penjualan")
        .onChange(of: viewModel.query) { viewModel.reload() }
        // `onAppear` rather than `task`: coming back from a detail that refunded must show the new sale.
        .onAppear { viewModel.reload() }
    }

    @ViewBuilder
    private var placeholder: some View {
        if viewModel.loadFailed {
            ContentUnavailableView("Riwayat tidak bisa dibuka", systemImage: "exclamationmark.triangle")
        } else if viewModel.sales.isEmpty, !viewModel.query.isEmpty {
            ContentUnavailableView("Tidak ditemukan", systemImage: "magnifyingglass")
        } else if viewModel.sales.isEmpty {
            ContentUnavailableView("Belum ada penjualan", systemImage: "clock")
        }
    }
}

private struct SaleRow: View {
    let sale: Sale

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("#\(sale.number)")
                Text(sale.occurredAt, format: DateFormat.dateTime)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(sale.total, format: MoneyFormat.rupiah).monospacedDigit()
                HStack(spacing: 6) {
                    if sale.receiptFailedAt != nil {
                        Image(systemName: "printer.slash")
                            .accessibilityLabel("Struk gagal dicetak")
                    }
                    if sale.voidedAt != nil {
                        Text("Dibatalkan").foregroundStyle(.red)
                    } else if sale.isRefund {
                        Text("Retur").foregroundStyle(.orange)
                    }
                    Text(sale.paymentLabel)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }
}

#if DEBUG
    #Preview {
        if let dependencies = try? Dependencies.inMemory() {
            NavigationStack {
                SalesHistoryView(dependencies: dependencies)
            }
        } else {
            Text("In-memory store failed")
        }
    }
#endif
