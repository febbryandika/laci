import SwiftUI
import UniformTypeIdentifiers

/// CSV export through the Files app (SPEC §5.2): a trading-day range and four files, each written
/// wherever the accountant wants it. Reached from Settings.
struct ExportView: View {
    @State private var viewModel: ExportViewModel

    init(dependencies: Dependencies) {
        _viewModel = State(initialValue: ExportViewModel(dependencies: dependencies))
    }

    var body: some View {
        Form {
            Section("Rentang hari") {
                DatePicker("Dari", selection: $viewModel.firstDay, displayedComponents: .date)
                    .accessibilityIdentifier("ExportView.firstDay")
                DatePicker("Sampai", selection: $viewModel.lastDay, displayedComponents: .date)
                    .accessibilityIdentifier("ExportView.lastDay")
            }
            .environment(\.timeZone, ShopDefaults.timeZone)
            .environment(\.locale, ShopDefaults.locale)
            Section {
                exportButton("Penjualan", kind: .sales)
                exportButton("Baris penjualan", kind: .saleLines)
                exportButton("Pergerakan stok", kind: .stockMovements)
                exportButton("Tutup kas", kind: .closeOuts)
            } header: {
                Text("Ekspor")
            } footer: {
                Text("Angka ditulis polos tanpa pemisah ribuan, dengan BOM UTF-8 agar terbaca di Excel.")
            }
            if let error = viewModel.error {
                Section {
                    message(for: error)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("ExportView.error")
                }
            }
        }
        .navigationTitle("Ekspor CSV")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: exporting, document: viewModel.document, contentType: .commaSeparatedText,
            defaultFilename: viewModel.filename
        ) { _ in
            viewModel.clearDocument()
        }
    }

    private var exporting: Binding<Bool> {
        Binding(
            get: { viewModel.document != nil },
            set: { presented in
                if !presented {
                    viewModel.clearDocument()
                }
            }
        )
    }

    private func exportButton(_ title: String, kind: ExportKind) -> some View {
        Button(title) { viewModel.prepare(kind) }
            .accessibilityIdentifier("ExportView.\(kind.rawValue)")
    }

    private func message(for error: ExportError) -> Text {
        switch error {
        case .rangeInverted: Text("Tanggal 'Dari' harus sebelum atau sama dengan 'Sampai'")
        case .fetchFailed: Text("Gagal membaca data untuk diekspor")
        }
    }
}
