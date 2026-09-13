import LaciCore
import SwiftUI

/// One product, read-only (SPEC §9): beside the list on an iPad, pushed on an iPhone.
struct CatalogueInspectorView: View {
    let product: Product

    var body: some View {
        Form {
            Section {
                LabeledContent("Nama") { Text(product.name) }
                LabeledContent("SKU") {
                    Text(product.sku).monospacedDigit()
                        .accessibilityIdentifier("CatalogueInspectorView.sku")
                }
                LabeledContent("Satuan") { Text(product.unit) }
            }
            Section("Harga") {
                LabeledContent("Harga jual") { MoneyText(product.price) }
                LabeledContent("Modal") { MoneyText(product.cost) }
            }
            Section("Stok") {
                LabeledContent("Lacak stok") { Text(product.tracksStock ? "Ya" : "Tidak") }
                if product.tracksStock {
                    LabeledContent("Stok") {
                        Text("\(product.stockOnHand, format: MoneyFormat.plain) \(product.unit)")
                    }
                }
            }
            Section("Barcode") {
                if product.barcodes.isEmpty {
                    Text("Tidak ada").foregroundStyle(.secondary)
                }
                ForEach(product.barcodes.sorted { $0.value < $1.value }, id: \.value) { barcode in
                    LabeledContent(barcode.value) { Text(barcode.symbology) }
                        .monospacedDigit()
                }
            }
            Section {
                LabeledContent("Diperbarui") { Text(product.updatedAt, format: DateFormat.dateTime) }
            }
        }
        .navigationTitle(product.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
