import Foundation
import LaciCore
import LaciMoney
import SwiftUI

/// The cart: the banners, the lines, the totals, and on the layouts with no catalogue pane the
/// search field and its results too. The one list every layout has.
struct SellCartPane: View {
    let viewModel: SellViewModel
    let printer: PrinterCoordinator
    let showsSearch: Bool
    @Binding var sheet: SellSheet?
    let focus: FocusState<SellField?>.Binding
    let onSearchSubmit: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        List {
            if let openPriorDay = viewModel.openPriorDay {
                openDaySection(openPriorDay)
            }
            if let failed = printer.failedSale {
                printFailureSection(failed)
            }
            if showsSearch {
                searchSection
                if !viewModel.query.isEmpty {
                    resultsSection
                }
            }
            cartSection
            totalsSection
        }
        // SPEC §9: Reduce Motion removes the cart-add animation.
        .animation(reduceMotion ? nil : .snappy, value: viewModel.lines.map(\.cart.sku))
        // The bare keys act only while the list itself has focus, so "-" typed into the search
        // field is still a character. Not in the ⌘ overlay, by design: they carry no modifier.
        .focusable()
        .focused(focus, equals: .cart)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) {
            viewModel.selectPrevious()
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.selectNext()
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "+")) { _ in
            viewModel.incrementSelected()
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "-")) { _ in
            viewModel.decrementSelected()
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SellView.cartPane")
    }

    /// SPEC §3.3.5: a day with no close-out stays open and banners on launch.
    private func openDaySection(_ day: Date) -> some View {
        Section {
            NavigationLink(value: SellRoute.closeOut) {
                Label("Hari \(day.formatted(DateFormat.day)) belum ditutup", systemImage: "exclamationmark.triangle")
            }
            .accessibilityIdentifier("SellView.openDay")
        }
    }

    /// SPEC §7.3: a failed print is a row, not a dialog. The sale is already saved.
    private func printFailureSection(_ failed: FailedSale) -> some View {
        Section {
            Label("Struk #\(failed.number) gagal dicetak", systemImage: "printer.slash")
            Button("Cetak ulang") { printer.reprint(saleID: failed.id) }
                .accessibilityIdentifier("SellView.reprint")
            Button("Tutup") { printer.dismissFailure() }
        }
        .accessibilityIdentifier("SellView.printFailure")
    }

    private var searchSection: some View {
        Section {
            SellSearchField(viewModel: viewModel, focus: focus, onSubmit: onSearchSubmit)
            if let notice = viewModel.scanNotice {
                Label(ScanNoticeText.label(notice), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("SellView.scanNotice")
            }
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
                        onSearchSubmit()
                    } label: {
                        LabeledContent(product.name) {
                            MoneyText(product.price)
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
                    viewModel.select(sku: line.cart.sku)
                    focus.wrappedValue = .cart
                    sheet = .editLine(sku: line.cart.sku)
                } label: {
                    CartRow(line: line, total: viewModel.lineTotal(for: line))
                }
                .tint(.primary)
                .listRowBackground(rowBackground(selected: viewModel.selectedSKU == line.cart.sku))
                .accessibilityIdentifier("SellView.line.\(line.cart.sku)")
            }
            .onDelete { offsets in
                for sku in offsets.map({ viewModel.lines[$0].cart.sku }) {
                    viewModel.remove(sku: sku)
                }
            }
        }
    }

    private func rowBackground(selected: Bool) -> Color? {
        selected ? Color.accentColor.opacity(0.12) : nil
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
            MoneyText(amount).monospacedDigit()
        }
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
                    MoneyText(line.cart.unitPrice)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if total.discount > .zero {
                    HStack(spacing: 4) {
                        Text("Diskon")
                        MoneyText(total.discount)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            MoneyText(total.net).monospacedDigit()
        }
    }
}
