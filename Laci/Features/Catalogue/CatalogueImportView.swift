import LaciCore
import SwiftUI
import UniformTypeIdentifiers

/// The CSV import sheet: pick a file, see what it would do, apply it or not (SPEC §3.2).
struct CatalogueImportView: View {
    let onImported: () -> Void
    @State private var viewModel: CatalogueImportViewModel
    @State private var pickerShown = false
    @Environment(\.dismiss) private var dismiss

    init(dependencies: Dependencies, onImported: @escaping () -> Void) {
        self.onImported = onImported
        _viewModel = State(initialValue: CatalogueImportViewModel(dependencies: dependencies))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Impor CSV")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Batal") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                            .accessibilityIdentifier("CatalogueImportView.cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Terapkan") { viewModel.commit() }
                            .disabled(!canCommit)
                            .accessibilityIdentifier("CatalogueImportView.commit")
                    }
                }
                .fileImporter(
                    isPresented: $pickerShown, allowedContentTypes: [.commaSeparatedText, .plainText]
                ) { result in
                    switch result {
                    case let .success(url): viewModel.read(url)
                    case .failure: viewModel.fail(.unopenable)
                    }
                }
                .onAppear {
                    if viewModel.phase == .picking {
                        pickerShown = true
                    }
                }
        }
    }

    private var canCommit: Bool {
        guard case let .previewed(preview) = viewModel.phase else { return false }
        return !preview.added.isEmpty || !preview.updated.isEmpty
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .picking:
            ContentUnavailableView {
                Label("Pilih berkas CSV", systemImage: "doc.text")
            } description: {
                Text("Kolom: \(CatalogueCSV.columns.joined(separator: ", "))")
            } actions: {
                Button("Pilih berkas") { pickerShown = true }
            }
        case let .previewed(preview):
            previewForm(preview)
        case let .failed(failure):
            ContentUnavailableView {
                Label("Impor gagal", systemImage: "exclamationmark.triangle")
            } description: {
                Text(failure.message)
            } actions: {
                Button("Pilih berkas lain") {
                    viewModel.reset()
                    pickerShown = true
                }
            }
            .accessibilityIdentifier("CatalogueImportView.failed")
        case let .done(added, updated):
            ContentUnavailableView {
                Label("Impor selesai", systemImage: "checkmark.circle")
            } description: {
                Text("\(added) ditambah, \(updated) diperbarui.")
            } actions: {
                Button("Selesai") {
                    onImported()
                    dismiss()
                }
                .accessibilityIdentifier("CatalogueImportView.done")
            }
        }
    }

    private func previewForm(_ preview: ImportPreview) -> some View {
        Form {
            Section {
                LabeledContent("Ditambah") { Text(preview.added.count, format: .number) }
                    .accessibilityIdentifier("CatalogueImportView.added")
                LabeledContent("Diperbarui") { Text(preview.updated.count, format: .number) }
                    .accessibilityIdentifier("CatalogueImportView.updated")
                LabeledContent("Ditolak") { Text(preview.rejected.count, format: .number) }
                    .accessibilityIdentifier("CatalogueImportView.rejected")
            } footer: {
                Text("Diterapkan seluruhnya atau tidak sama sekali. Baris yang ditolak dilewati.")
            }
            if !preview.rejected.isEmpty {
                Section("Ditolak") {
                    ForEach(preview.rejected, id: \.line) { rejection in
                        VStack(alignment: .leading, spacing: 2) {
                            if let sku = rejection.sku {
                                Text("Baris \(rejection.line) · \(sku)")
                            } else {
                                Text("Baris \(rejection.line)")
                            }
                            Text(ImportErrorText.label(rejection.reason))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
