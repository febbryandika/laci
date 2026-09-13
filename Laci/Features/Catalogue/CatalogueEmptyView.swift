import SwiftUI

/// SPEC §9: an empty catalogue offers import and add-first-product and nothing else. Shared by the
/// catalogue screen and the sell screen, so the two offers are the same everywhere.
struct CatalogueEmptyView: View {
    let onImport: () -> Void
    let onAdd: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Katalog kosong", systemImage: "shippingbox")
        } description: {
            Text("Impor berkas CSV, atau tambah produk pertama.")
        } actions: {
            Button("Tambah produk pertama", action: onAdd)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("Catalogue.addFirst")
            Button("Impor CSV", action: onImport)
                .accessibilityIdentifier("Catalogue.importCSV")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Catalogue.empty")
    }
}
