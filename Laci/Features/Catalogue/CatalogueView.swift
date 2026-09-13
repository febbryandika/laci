import LaciCore
import SwiftUI

/// The catalogue (SPEC §9): a list with an inspector beside it on an iPad, pushed on an iPhone.
/// Read-only; the empty state offers the import and the first product and nothing else.
struct CatalogueView: View {
    private enum Sheet: String, Identifiable {
        case importCSV
        case newProduct

        var id: String {
            rawValue
        }
    }

    private let dependencies: Dependencies
    @State private var viewModel: CatalogueViewModel
    @State private var sheet: Sheet?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: CatalogueViewModel(dependencies: dependencies))
    }

    var body: some View {
        content
            .navigationTitle("Katalog")
            .toolbar {
                ToolbarItem {
                    Button {
                        sheet = .importCSV
                    } label: {
                        Label("Impor CSV", systemImage: "square.and.arrow.down")
                    }
                    .accessibilityIdentifier("CatalogueView.import")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        sheet = .newProduct
                    } label: {
                        Label("Tambah produk", systemImage: "plus")
                    }
                    .accessibilityIdentifier("CatalogueView.add")
                }
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .importCSV:
                    CatalogueImportView(dependencies: dependencies) { viewModel.load() }
                case .newProduct:
                    NewProductView(pending: nil, dependencies: dependencies) { product in
                        viewModel.load()
                        viewModel.selectedSKU = product.sku
                        self.sheet = nil
                    }
                }
            }
            .onAppear { viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.loadFailed {
            ContentUnavailableView("Katalog tidak bisa dibuka", systemImage: "exclamationmark.triangle")
        } else if viewModel.products.isEmpty {
            CatalogueEmptyView(onImport: { sheet = .importCSV }, onAdd: { sheet = .newProduct })
        } else if horizontalSizeClass == .regular {
            HStack(spacing: 0) {
                list
                    .frame(minWidth: 320, idealWidth: 380, maxWidth: 440)
                Divider()
                inspector
                    .frame(maxWidth: .infinity)
            }
        } else {
            list
        }
    }

    private var list: some View {
        List(viewModel.results, id: \.sku) { product in
            row(product)
        }
        .searchable(text: $viewModel.query, prompt: "Cari produk atau SKU")
        .overlay {
            if viewModel.results.isEmpty {
                ContentUnavailableView.search(text: viewModel.query)
            }
        }
        .accessibilityIdentifier("CatalogueView.list")
    }

    /// Selection beside the list on an iPad; a push on an iPhone.
    @ViewBuilder
    private func row(_ product: Product) -> some View {
        if horizontalSizeClass == .regular {
            Button {
                viewModel.selectedSKU = product.sku
            } label: {
                CatalogueRow(product: product)
            }
            .tint(.primary)
            .listRowBackground(viewModel.selectedSKU == product.sku ? Color.accentColor.opacity(0.12) : nil)
            .accessibilityIdentifier("CatalogueView.row.\(product.sku)")
        } else {
            NavigationLink {
                CatalogueInspectorView(product: product)
            } label: {
                CatalogueRow(product: product)
            }
            .accessibilityIdentifier("CatalogueView.row.\(product.sku)")
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if let product = viewModel.selected {
            CatalogueInspectorView(product: product)
        } else {
            ContentUnavailableView("Pilih produk", systemImage: "shippingbox")
        }
    }
}

/// The price drops under the name at accessibility sizes, as every two-column row does.
private struct CatalogueRow: View {
    let product: Product
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                details
                MoneyText(product.price).monospacedDigit()
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                details
                Spacer()
                MoneyText(product.price).monospacedDigit()
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(product.name)
            Text(verbatim: "\(product.sku) · \(product.unit)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
