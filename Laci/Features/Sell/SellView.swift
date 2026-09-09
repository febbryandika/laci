import Foundation
import LaciCore
import LaciMoney
import SwiftUI

/// The launch screen (SPEC §3.1.1): one column, keyboard only. The three-pane iPad layout is a
/// later phase and builds on the same view model.
struct SellView: View {
    private enum Sheet: Identifiable, Hashable {
        case editLine(sku: String)
        case saleDiscount
        case tender

        var id: String {
            switch self {
            case let .editLine(sku): "line-\(sku)"
            case .saleDiscount: "discount"
            case .tender: "tender"
            }
        }
    }

    @State private var viewModel: SellViewModel
    @State private var sheet: Sheet?

    init(dependencies: Dependencies) {
        _viewModel = State(initialValue: SellViewModel(dependencies: dependencies))
    }

    var body: some View {
        NavigationStack {
            List {
                searchSection
                if !viewModel.query.isEmpty {
                    resultsSection
                }
                cartSection
                totalsSection
            }
            .navigationTitle("Jual")
            .safeAreaInset(edge: .bottom) { payButton }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case let .editLine(sku): CartLineEditor(sku: sku, viewModel: viewModel)
                case .saleDiscount: SaleDiscountEditor(viewModel: viewModel)
                case .tender: TenderView(viewModel: viewModel)
                }
            }
            .task { viewModel.loadCatalogue() }
        }
    }

    private var searchSection: some View {
        Section {
            TextField("Cari produk atau SKU", text: $viewModel.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { viewModel.addFirstResult() }
                .accessibilityIdentifier("SellView.search")
        }
    }

    private var resultsSection: some View {
        Section("Hasil") {
            if viewModel.catalogueFailed {
                Text("Katalog tidak bisa dibuka")
            } else if viewModel.catalogue.isEmpty {
                Text("Katalog kosong")
            } else if viewModel.results.isEmpty {
                Text("Tidak ditemukan")
            } else {
                ForEach(viewModel.results.prefix(20), id: \.sku) { product in
                    Button {
                        viewModel.add(product)
                        viewModel.query = ""
                    } label: {
                        LabeledContent(product.name) {
                            Text(product.price, format: MoneyFormat.rupiah)
                        }
                    }
                    .tint(.primary)
                }
            }
        }
    }

    private var cartSection: some View {
        Section("Keranjang") {
            if viewModel.lines.isEmpty {
                Text("Keranjang kosong").foregroundStyle(.secondary)
            }
            ForEach(viewModel.lines, id: \.cart.sku) { line in
                Button {
                    sheet = .editLine(sku: line.cart.sku)
                } label: {
                    CartRow(line: line, total: viewModel.lineTotal(for: line))
                }
                .tint(.primary)
            }
            .onDelete { offsets in
                for sku in offsets.map({ viewModel.lines[$0].cart.sku }) {
                    viewModel.remove(sku: sku)
                }
            }
        }
    }

    private var totalsSection: some View {
        Section {
            amountRow("Subtotal", viewModel.totals.subtotal)
            if viewModel.totals.lineDiscounts > .zero {
                amountRow("Diskon baris", viewModel.totals.lineDiscounts)
            }
            Button {
                sheet = .saleDiscount
            } label: {
                amountRow("Diskon penjualan", viewModel.totals.saleDiscount)
            }
            .tint(.primary)
            .disabled(viewModel.lines.isEmpty)
            amountRow("Total", viewModel.totals.grandTotal).bold()
            amountRow("Tunai (dibulatkan)", viewModel.cashTotal)
        }
    }

    private func amountRow(_ label: LocalizedStringKey, _ amount: Money) -> some View {
        LabeledContent(label) {
            Text(amount.amount, format: MoneyFormat.rupiah).monospacedDigit()
        }
    }

    private var payButton: some View {
        Button {
            sheet = .tender
        } label: {
            Text("Bayar")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.lines.isEmpty)
        .padding()
        .background(.bar)
        .accessibilityIdentifier("SellView.pay")
    }
}

private struct CartRow: View {
    let line: SaleDraft.Line
    let total: LineTotal

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.cart.name)
                HStack(spacing: 4) {
                    Text(line.cart.quantity, format: MoneyFormat.plain)
                    Text("×")
                    Text(line.cart.unitPrice.amount, format: MoneyFormat.rupiah)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if total.discount > .zero {
                    HStack(spacing: 4) {
                        Text("Diskon")
                        Text(total.discount.amount, format: MoneyFormat.rupiah)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(total.net.amount, format: MoneyFormat.rupiah).monospacedDigit()
        }
    }
}

#if DEBUG
    /// A populated store so the canvas shows a real cart; the fixture load is best-effort.
    @MainActor
    private func previewDependencies() -> Dependencies? {
        guard let dependencies = try? Dependencies.inMemory() else { return nil }
        _ = try? DebugFixtures.loadWarung200(into: dependencies)
        return dependencies
    }

    #Preview {
        if let dependencies = previewDependencies() {
            SellView(dependencies: dependencies)
        } else {
            Text("In-memory store failed")
        }
    }
#endif
