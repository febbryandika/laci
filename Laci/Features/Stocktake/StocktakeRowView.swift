import LaciMoney
import SwiftUI

/// One counted SKU with its variance column (SPEC §9). At accessibility sizes the three columns
/// no longer fit beside each other, so the count and the variance drop under the name.
struct StocktakeRowView: View {
    let row: StocktakeRow
    @Binding var counted: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric private var fieldWidth = 72.0

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                title
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    countField
                    Spacer()
                    variance
                }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                title
                Spacer()
                countField
                variance.frame(minWidth: 96, alignment: .trailing)
            }
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.name)
            Text("\(row.sku) · sistem \(row.systemQuantity, format: MoneyFormat.plain) \(row.unit)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var countField: some View {
        TextField("Hitung", text: $counted)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(minWidth: fieldWidth)
            .fixedSize(horizontal: true, vertical: false)
            .textFieldStyle(.roundedBorder)
            .foregroundStyle(row.counted == nil ? .red : .primary)
            .accessibilityIdentifier("StocktakeView.counted.\(row.sku)")
    }

    private var variance: some View {
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
    }
}
