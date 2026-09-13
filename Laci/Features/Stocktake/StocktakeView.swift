import LaciCore
import LaciMoney
import SwiftUI

/// The running scan list with a variance column (SPEC §9). Pushed from the sell screen; the same
/// camera sheet and keyboard wedge feed it.
struct StocktakeView: View {
    private enum Field: Hashable {
        case code
        case wedge
    }

    private let dependencies: Dependencies
    @State private var viewModel: StocktakeViewModel
    @State private var code = ""
    @State private var showScanner = false
    @State private var confirmApply = false
    @State private var wedgeEnabled = false
    @State private var isVisible = false
    @FocusState private var focus: Field?

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: StocktakeViewModel(dependencies: dependencies))
    }

    var body: some View {
        List {
            entrySection
            if let applied = viewModel.appliedCount, viewModel.rows.isEmpty {
                Section {
                    Text(applied == 0 ? "Stok sesuai, tidak ada penyesuaian." : "\(applied) SKU disesuaikan.")
                        .accessibilityIdentifier("StocktakeView.applied")
                }
            }
            if !viewModel.rows.isEmpty {
                rowsSection
                totalSection
            }
            if let error = viewModel.error {
                Section {
                    message(for: error)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("StocktakeView.error")
                }
            }
        }
        .navigationTitle("Stok opname")
        .toolbar {
            ToolbarItem {
                Button {
                    showScanner = true
                } label: {
                    Label("Pindai", systemImage: "barcode.viewfinder")
                }
                .accessibilityIdentifier("StocktakeView.scan")
            }
            ToolbarItem {
                NavigationLink {
                    StockAdjustmentView(dependencies: dependencies)
                } label: {
                    Label("Penyesuaian", systemImage: "plus.forwardslash.minus")
                }
                .accessibilityIdentifier("StocktakeView.adjust")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Terapkan") { confirmApply = true }
                    .disabled(!viewModel.canApply)
                    .accessibilityIdentifier("StocktakeView.apply")
            }
        }
        .sheet(isPresented: $showScanner) { ScannerSheet(viewModel: viewModel) }
        .overlay(alignment: .topLeading) { wedgeField }
        .scanFeedback(trigger: viewModel.scansAccepted, isActive: !showScanner)
        .confirmationDialog(applyTitle, isPresented: $confirmApply, titleVisibility: .visible) {
            Button("Terapkan", role: .destructive) { viewModel.apply() }
        } message: {
            Text("SKU yang tidak dipindai tidak diubah.")
        }
        .onAppear {
            wedgeEnabled = ScannerSettings.wedgeEnabled()
            isVisible = true
            focusWedge()
        }
        .onDisappear { isVisible = false }
        .onChange(of: showScanner) {
            if !showScanner {
                viewModel.clearScanNotice()
                focusWedge()
            }
        }
    }

    private var applyTitle: String {
        let changed = viewModel.changedRows.count
        return changed == 0 ? "Selesaikan hitungan tanpa penyesuaian?" : "Terapkan \(changed) penyesuaian stok?"
    }

    private var entrySection: some View {
        Section {
            TextField("Kode / SKU", text: $code)
                .focused($focus, equals: .code)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit {
                    viewModel.didRead(code: code, symbology: nil)
                    code = ""
                    focus = .code
                }
                .accessibilityIdentifier("StocktakeView.code")
            if let notice = viewModel.scanNotice {
                Text(ScanNoticeText.label(notice))
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("StocktakeView.notice")
            }
        } footer: {
            Text("Pindai atau ketik kode. Pindai lagi untuk menambah hitungan, atau ubah angkanya.")
        }
    }

    private var rowsSection: some View {
        Section("Hitungan") {
            ForEach(viewModel.rows) { row in
                StocktakeRowView(row: row, counted: countedBinding(for: row.sku))
            }
            .onDelete { viewModel.remove(atOffsets: $0) }
        }
    }

    private var totalSection: some View {
        Section {
            LabeledContent("Total selisih (modal)") {
                MoneyText(viewModel.totalVarianceValue)
                    .monospacedDigit()
                    .foregroundStyle(viewModel.totalVarianceValue < .zero ? .red : .primary)
                    .accessibilityIdentifier("StocktakeView.total")
            }
        }
    }

    private func countedBinding(for sku: String) -> Binding<String> {
        Binding(
            get: { viewModel.rows.first { $0.sku == sku }?.countedText ?? "" },
            set: { viewModel.setCounted($0, for: sku) }
        )
    }

    private func message(for error: StocktakeError) -> Text {
        switch error {
        case let .invalidCount(sku): Text("Hitungan \(sku) tidak valid")
        case .applyFailed: Text("Gagal menerapkan stok opname, coba lagi")
        }
    }

    private var wedgeField: some View {
        WedgeField(focus: $focus, field: .wedge, identifier: "StocktakeView.wedge") {
            viewModel.didRead(code: $0, symbology: nil)
        }
    }

    /// Same rule as the sell screen: only while showing with no sheet up, with one re-check after
    /// the navigation transition, because a focus request made during it is dropped silently.
    private func focusWedge() {
        guard wedgeEnabled, isVisible, !showScanner else { return }
        focus = .wedge
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            if wedgeEnabled, isVisible, !showScanner, focus == nil {
                focus = .wedge
            }
        }
    }
}

private struct StocktakeRowView: View {
    let row: StocktakeRow
    @Binding var counted: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                Text("\(row.sku) · sistem \(row.systemQuantity, format: MoneyFormat.plain) \(row.unit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField("Hitung", text: $counted)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
                .textFieldStyle(.roundedBorder)
                .foregroundStyle(row.counted == nil ? .red : .primary)
                .accessibilityIdentifier("StocktakeView.counted.\(row.sku)")
            VStack(alignment: .trailing, spacing: 2) {
                if let variance = row.variance, let value = row.varianceValue {
                    Text(variance, format: MoneyFormat.plain.sign(strategy: .always(includingZero: false)))
                        .monospacedDigit()
                    MoneyText(value)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(value < .zero ? .red : .secondary)
                } else {
                    Text("—")
                }
            }
            .frame(minWidth: 96, alignment: .trailing)
        }
    }
}
