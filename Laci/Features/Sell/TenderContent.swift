import Foundation
import LaciCore
import LaciMoney
import SwiftUI

enum TenderMethod: Hashable, CaseIterable {
    case cash
    case qris
    case transfer
}

/// Checkout (SPEC §1, §8.3): cash with quick-tender, a keypad and change, or QRIS / transfer with
/// a reference. The same content sits in the tender pane on an iPad and in a sheet on an iPhone;
/// the checkout itself is the view model's, and this view only decides where a locked shop goes.
struct TenderContent: View {
    enum Style {
        case inline
        case sheet
    }

    let viewModel: SellViewModel
    let printer: PrinterCoordinator
    let style: Style
    let focus: FocusState<SellField?>.Binding
    let presentPaywall: () -> Void
    let onNewSale: () -> Void
    @State private var method: TenderMethod = .cash
    @State private var amountText = ""
    @State private var reference = ""
    /// The last sale this view has already shown, so only a sale rung up after it appears.
    @State private var acknowledgedSaleID: UUID?

    init(
        viewModel: SellViewModel, printer: PrinterCoordinator, style: Style, focus: FocusState<SellField?>.Binding,
        presentPaywall: @escaping () -> Void, onNewSale: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.printer = printer
        self.style = style
        self.focus = focus
        self.presentPaywall = presentPaywall
        self.onNewSale = onNewSale
        _acknowledgedSaleID = State(initialValue: viewModel.lastSale?.id)
    }

    /// One scroll view for both states: a container swapped under a sheet mid-checkout has been
    /// seen to come back with no size until the next update.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let completed {
                    TenderCompletedView(sale: completed, printer: printer, onNewSale: newSale)
                } else {
                    formContent
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            if completed == nil {
                payButton
            }
        }
        .onChange(of: method) { viewModel.clearTenderError() }
        .onDisappear { viewModel.clearTenderError() }
    }

    /// Derived, not set on checkout: a ⌘⏎ checkout that never touched this view still shows here.
    private var completed: Sale? {
        guard let sale = viewModel.lastSale, sale.id != acknowledgedSaleID else { return nil }
        return sale
    }

    @ViewBuilder
    private var formContent: some View {
        methodPicker
        switch method {
        case .cash: cashSection
        case .qris, .transfer: nonCashSection
        }
        if let error = viewModel.tenderError {
            message(for: error)
                .foregroundStyle(.red)
                .accessibilityIdentifier("TenderView.error")
        }
    }

    private var methodPicker: some View {
        AdaptivePicker("Metode", selection: $method) {
            Text("Tunai").tag(TenderMethod.cash)
            Text("QRIS").tag(TenderMethod.qris)
            Text("Transfer").tag(TenderMethod.transfer)
        }
        .accessibilityIdentifier("Tender.method")
    }

    // MARK: Cash

    private var tendered: Money? {
        DecimalInput.parse(amountText).map(Money.init)
    }

    @ViewBuilder
    private var cashSection: some View {
        LabeledContent("Total tunai") {
            MoneyText(viewModel.cashTotal).bold()
                .accessibilityIdentifier("Tender.total")
        }
        Text("Uang diterima").font(.headline)
        if !viewModel.lines.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))]) {
                ForEach(viewModel.cashSuggestions, id: \.amount) { amount in
                    Button {
                        attemptCash(amount)
                    } label: {
                        MoneyText(amount)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("Tender.chip.\(amount.amount.formatted(MoneyFormat.plain))")
                }
            }
        }
        TextField("Jumlah lain", text: $amountText)
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
            .focused(focus, equals: .tenderAmount)
            .accessibilityIdentifier("Tender.tendered")
        NumericKeypad(text: $amountText)
        if let tendered {
            if let settlement = viewModel.settle(tendered: tendered) {
                LabeledContent("Kembalian") {
                    MoneyText(settlement.change).bold()
                        .accessibilityIdentifier("Tender.change")
                }
            } else {
                Text("Uang kurang").foregroundStyle(.red)
            }
        }
    }

    // MARK: Non-cash

    @ViewBuilder
    private var nonCashSection: some View {
        LabeledContent("Total") {
            MoneyText(viewModel.totals.grandTotal).bold()
                .accessibilityIdentifier("Tender.total")
        }
        TextField("Nomor referensi", text: $reference)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("Tender.reference")
    }

    // MARK: Paying

    private var canPay: Bool {
        guard !viewModel.lines.isEmpty else { return false }
        return method == .cash ? tendered != nil : true
    }

    private var payButton: some View {
        Button(action: attempt) {
            Text("Bayar")
                .frame(maxWidth: .infinity, minHeight: 60)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canPay)
        .padding()
        .background(.bar)
        .accessibilityIdentifier(style == .inline ? "SellView.pay" : "TenderView.pay")
    }

    private func attempt() {
        switch method {
        case .cash:
            if let tendered {
                attemptCash(tendered)
            }
        case .qris:
            attemptNonCash(.qris)
        case .transfer:
            attemptNonCash(.transfer)
        }
    }

    /// SPEC §5.1: the entitlement is checked at the checkout button and nowhere else.
    private func attemptCash(_ amount: Money) {
        guard !viewModel.isCheckoutLocked() else { return presentPaywall() }
        viewModel.checkoutCash(tendered: amount)
    }

    private func attemptNonCash(_ method: NonCashMethod) {
        guard !viewModel.isCheckoutLocked() else { return presentPaywall() }
        viewModel.checkoutNonCash(method, reference: reference)
    }

    private func newSale() {
        acknowledgedSaleID = viewModel.lastSale?.id
        amountText = ""
        reference = ""
        method = .cash
        onNewSale()
    }

    @ViewBuilder
    private func message(for error: TenderError) -> some View {
        switch error {
        case .emptyCart: Text("Keranjang kosong")
        case let .cashShort(rounded):
            Text("Uang kurang dari \(rounded.amount.formatted(MoneyFormat.rupiah))")
                .accessibilityLabel(Text("Uang kurang dari \(rounded.amount.formatted(MoneyFormat.spoken))"))
        case .missingReference: Text("Nomor referensi wajib diisi")
        case .commitFailed: Text("Penjualan gagal disimpan, coba lagi")
        case .locked: Text("Masa percobaan habis. Buka Laci dari tombol Bayar atau Pengaturan.")
        }
    }
}
