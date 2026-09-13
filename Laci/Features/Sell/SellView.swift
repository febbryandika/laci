import Foundation
import LaciCore
import LaciMoney
import SwiftUI

/// The launch screen (SPEC §3.1.1) and the layout decision (SPEC §9): three panes on an iPad, two
/// at AX3, and on an iPhone the cart with the catalogue and the keypad as sheets. Everything the
/// panes share (the view model, the sheet, the focus, the pushed screens) is owned here.
struct SellView: View {
    private let dependencies: Dependencies
    private let unlock: UnlockStore
    @State private var viewModel: SellViewModel
    @State private var sheet: SellSheet?
    @State private var path: [SellRoute] = []
    @FocusState private var focus: SellField?
    @State private var wedgeEnabled = false
    @State private var isVisible = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(dependencies: Dependencies, unlock: UnlockStore) {
        self.dependencies = dependencies
        self.unlock = unlock
        _viewModel = State(initialValue: SellViewModel(dependencies: dependencies, unlock: unlock))
    }

    private var layout: SellLayout {
        SellLayout.resolve(
            horizontal: horizontalSizeClass, vertical: verticalSizeClass, dynamicTypeSize: dynamicTypeSize
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            layoutBody
                .background { shortcuts }
                .navigationTitle("Jual")
                .navigationBarTitleDisplayMode(layout == .compact ? .automatic : .inline)
                .navigationDestination(for: SellRoute.self) { destination($0) }
                .toolbar { toolbar }
                .sheet(item: $sheet) { sheetContent($0) }
                // Always present, so focus can be given to it during a navigation transition; the
                // Settings toggle only decides whether it is ever focused.
                .overlay(alignment: .topLeading) { wedgeField }
                .scanFeedback(trigger: viewModel.scansAccepted, isActive: sheet == nil)
                .task { viewModel.loadCatalogue() }
                // `onAppear`, not `task`: coming back from the close-out screen must drop the
                // banner, and coming back from Settings must pick up the wedge toggle.
                .onAppear {
                    viewModel.refreshCloseOutStatus()
                    wedgeEnabled = ScannerSettings.wedgeEnabled()
                    isVisible = true
                    focusWedge()
                }
                .onDisappear { isVisible = false }
                // An unknown code swaps whichever sheet is up for the create form (SPEC §3.1.2).
                .onChange(of: viewModel.pendingBarcode) {
                    if let pending = viewModel.pendingBarcode {
                        sheet = .newProduct(pending)
                    }
                }
                .onChange(of: sheet) {
                    if sheet == nil {
                        // Cleared here rather than on save, so cancelling the form also lets the
                        // same code trigger it again.
                        viewModel.clearPendingBarcode()
                        focusWedge()
                    }
                }
        }
    }

    @ViewBuilder
    private var layoutBody: some View {
        switch layout {
        case .threePane:
            HStack(spacing: 0) {
                SellCataloguePane(viewModel: viewModel, sheet: $sheet, focus: $focus, onAdd: focusWedge)
                    .frame(minWidth: 240, idealWidth: 320, maxWidth: 400)
                Divider()
                cartPane(showsSearch: false)
                Divider()
                tenderPane.frame(width: 320)
            }
        case .twoPane:
            HStack(spacing: 0) {
                cartPane(showsSearch: true)
                Divider()
                tenderPane.frame(width: 400)
            }
        case .compact:
            cartPane(showsSearch: true)
                .safeAreaInset(edge: .bottom) { payButton }
        }
    }

    private func cartPane(showsSearch: Bool) -> some View {
        SellCartPane(
            viewModel: viewModel, printer: dependencies.printer, showsSearch: showsSearch, sheet: $sheet,
            focus: $focus, onSearchSubmit: focusWedge
        )
        .frame(maxWidth: .infinity)
    }

    private var tenderPane: some View {
        TenderContent(
            viewModel: viewModel, printer: dependencies.printer, style: .inline, focus: $focus,
            presentPaywall: { sheet = .paywall }, onNewSale: focusWedge
        )
        .background(Color(.systemGroupedBackground))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SellView.tenderPane")
    }

    /// The iPhone's way into the keypad sheet. SPEC §5.1: the entitlement is checked here and at
    /// the pane's own button, nowhere else.
    private var payButton: some View {
        Button {
            sheet = viewModel.isCheckoutLocked() ? .paywall : .tender
        } label: {
            Text("Bayar")
                .frame(maxWidth: .infinity, minHeight: 60)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.lines.isEmpty)
        .padding()
        .background(.bar)
        .accessibilityIdentifier("SellView.pay")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Button {
                sheet = .scanner
            } label: {
                Label("Pindai", systemImage: "barcode.viewfinder")
            }
            .accessibilityIdentifier("SellView.scan")
        }
        ToolbarItem {
            Button {
                path.append(.closeOut)
            } label: {
                Label("Tutup kas", systemImage: "tray.and.arrow.down")
            }
            .keyboardShortcut("l")
            .accessibilityIdentifier("SellView.closeOut")
        }
        ToolbarItem {
            Button {
                path.append(.history)
            } label: {
                Label("Riwayat", systemImage: "clock")
            }
            .accessibilityIdentifier("SellView.history")
        }
        ToolbarItem {
            Button {
                path.append(.stocktake)
            } label: {
                Label("Stok opname", systemImage: "list.clipboard")
            }
            .accessibilityIdentifier("SellView.stocktake")
        }
        if layout != .compact {
            ToolbarItem {
                Button {
                    path.append(.catalogue)
                } label: {
                    Label("Katalog", systemImage: "shippingbox")
                }
                .accessibilityIdentifier("SellView.catalogue")
            }
        }
        ToolbarItem {
            Button {
                path.append(.settings)
            } label: {
                Label("Pengaturan", systemImage: "gearshape")
            }
            .accessibilityIdentifier("SellView.settings")
        }
    }

    @ViewBuilder
    private func destination(_ route: SellRoute) -> some View {
        switch route {
        case .closeOut: CloseOutView(dependencies: dependencies)
        case .history: SalesHistoryView(dependencies: dependencies)
        case .stocktake: StocktakeView(dependencies: dependencies)
        case .settings: SettingsView(dependencies: dependencies)
        case .catalogue: CatalogueView(dependencies: dependencies)
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: SellSheet) -> some View {
        switch sheet {
        case let .editLine(sku): CartLineEditor(sku: sku, viewModel: viewModel)
        case .saleDiscount: SaleDiscountEditor(viewModel: viewModel)
        case .tender: TenderView(viewModel: viewModel, printer: dependencies.printer, focus: $focus)
        case .scanner: ScannerSheet(viewModel: viewModel)
        case let .newProduct(pending):
            NewProductView(pending: pending, dependencies: dependencies) { product in
                viewModel.loadCatalogue()
                viewModel.add(product)
                self.sheet = nil
            }
        case .paywall: PaywallView(unlock: unlock, origin: .checkout)
        case .importCatalogue:
            CatalogueImportView(dependencies: dependencies) { viewModel.loadCatalogue() }
        }
    }
}

private extension SellView {
    var shortcuts: some View {
        SellShortcuts(
            viewModel: viewModel, printer: dependencies.printer,
            focusSearch: { focus = .search },
            checkoutExactCash: checkoutExactCash,
            openTender: openTender,
            escape: escape
        )
    }

    /// ⌘⏎: the rounded cash total, tendered exactly. SPEC §5.1 gates it like any checkout button.
    func checkoutExactCash() {
        guard !viewModel.lines.isEmpty else { return }
        guard !viewModel.isCheckoutLocked() else { return sheet = .paywall }
        viewModel.checkoutCash(tendered: viewModel.cashTotal)
    }

    /// ⌘⇧⏎: the keypad sheet on an iPhone, the amount field of the pane on an iPad.
    func openTender() {
        if layout.showsTenderPane {
            focus = .tenderAmount
        } else {
            sheet = viewModel.isCheckoutLocked() ? .paywall : .tender
        }
    }

    /// Esc: clear the search, else drop the selection, else leave the search field. Never the cart.
    func escape() {
        if !viewModel.query.isEmpty {
            viewModel.query = ""
        } else if viewModel.selectedSKU != nil {
            viewModel.select(sku: nil)
        } else if focus == .search {
            focus = .cart
        }
    }

    var wedgeField: some View {
        WedgeField(focus: $focus, field: .wedge, identifier: "SellView.wedge") {
            viewModel.didRead(code: $0, symbology: nil)
        }
    }

    /// Only while this screen is showing with no sheet up, so a pushed or presented screen's own
    /// fields are never fought for focus.
    func focusWedge() {
        guard wedgeEnabled, isVisible, sheet == nil else { return }
        focus = .wedge
        // `onAppear` runs while the navigation pop is still animating, and a focus request made
        // then is dropped without a trace. One re-check after the transition covers it.
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            if wedgeEnabled, isVisible, sheet == nil, focus == nil {
                focus = .wedge
            }
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
            SellView(dependencies: dependencies, unlock: UnlockStore())
        } else {
            Text(verbatim: "In-memory store failed")
        }
    }
#endif
