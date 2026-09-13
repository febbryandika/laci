import LaciCore
import SwiftUI

/// The catalogue grid of the three-pane layout (SPEC §9): search on top, every product as a tile,
/// one tap to add. The list of results in the cart pane is the same data on the other layouts.
struct SellCataloguePane: View {
    let viewModel: SellViewModel
    @Binding var sheet: SellSheet?
    let focus: FocusState<SellField?>.Binding
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                SellSearchField(viewModel: viewModel, focus: focus, onSubmit: onAdd)
                    .textFieldStyle(.roundedBorder)
                if let notice = viewModel.scanNotice {
                    Label(ScanNoticeText.label(notice), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("SellView.scanNotice")
                }
            }
            .padding()
            Divider()
            content
        }
        .background(Color(.systemGroupedBackground))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SellView.cataloguePane")
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.catalogueFailed {
            ContentUnavailableView("Katalog tidak bisa dibuka", systemImage: "exclamationmark.triangle")
        } else if viewModel.catalogue.isEmpty {
            CatalogueEmptyView(onImport: { sheet = .importCatalogue }, onAdd: { sheet = .newProduct(nil) })
        } else if viewModel.results.isEmpty {
            ContentUnavailableView.search(text: viewModel.query)
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach(viewModel.results, id: \.sku) { product in
                    tile(product)
                }
            }
            .padding()
        }
    }

    private func tile(_ product: Product) -> some View {
        Button {
            viewModel.add(product)
            onAdd()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                MoneyText(product.price)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("SellView.catalogue.\(product.sku)")
    }
}
