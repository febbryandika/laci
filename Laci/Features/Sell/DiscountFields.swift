import Foundation
import LaciMoney
import SwiftUI

/// Editing state for a `Discount`: the kind and the typed value are separate so a Picker can bind
/// to the kind, and the value is dropped when the kind changes ("10" means different things).
struct DiscountDraft: Hashable {
    enum Kind: Hashable, CaseIterable {
        case none, amount, percent
    }

    var kind: Kind
    var valueText: String

    init(_ discount: Discount) {
        switch discount {
        case .none:
            kind = .none
            valueText = ""
        case let .amount(money):
            kind = .amount
            valueText = money.amount.formatted(MoneyFormat.plain)
        case let .percent(percent):
            kind = .percent
            valueText = percent.formatted(MoneyFormat.plain)
        }
    }

    var discount: Discount {
        switch kind {
        case .none: .none
        case .amount: DecimalInput.parse(valueText).map { .amount(Money($0)) } ?? .none
        case .percent: DecimalInput.parse(valueText).map { .percent($0) } ?? .none
        }
    }
}

struct DiscountFields: View {
    @Binding var draft: DiscountDraft

    var body: some View {
        Picker("Jenis diskon", selection: $draft.kind) {
            Text("Tanpa").tag(DiscountDraft.Kind.none)
            Text("Nominal").tag(DiscountDraft.Kind.amount)
            Text("Persen").tag(DiscountDraft.Kind.percent)
        }
        .pickerStyle(.segmented)
        .onChange(of: draft.kind) { draft.valueText = "" }
        if draft.kind != .none {
            TextField(draft.kind == .amount ? "Rp" : "%", text: $draft.valueText)
                .keyboardType(.numberPad)
        }
    }
}
