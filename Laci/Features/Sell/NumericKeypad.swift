import SwiftUI

/// One key of the tender keypad.
nonisolated enum KeypadKey: Hashable, Sendable {
    case digit(Character)
    case tripleZero
    case delete

    var identifier: String {
        switch self {
        case let .digit(character): String(character)
        case .tripleZero: "000"
        case .delete: "delete"
        }
    }
}

/// The edit a key makes to the typed amount. Pure, so it is tested without a view.
nonisolated enum KeypadEdit {
    static func apply(_ key: KeypadKey, to text: String) -> String {
        switch key {
        case let .digit(character):
            // "0" then "5" is 5, never "05".
            if text == "0" {
                String(character)
            } else {
                text + String(character)
            }
        case .tripleZero:
            if text.isEmpty || text == "0" {
                text
            } else {
                text + "000"
            }
        case .delete:
            String(text.dropLast())
        }
    }
}

/// SPEC §9: tender keys are hit with a thumb at speed, so each is at least 60pt square and grows
/// with Dynamic Type from there.
struct NumericKeypad: View {
    @Binding var text: String
    @ScaledMetric(relativeTo: .title2) private var keyHeight = 60.0

    private static let rows: [[KeypadKey]] = [
        [.digit("1"), .digit("2"), .digit("3")],
        [.digit("4"), .digit("5"), .digit("6")],
        [.digit("7"), .digit("8"), .digit("9")],
        [.tripleZero, .digit("0"), .delete],
    ]

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(Self.rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { key in
                        keyButton(key)
                    }
                }
            }
        }
    }

    private func keyButton(_ key: KeypadKey) -> some View {
        Button {
            text = KeypadEdit.apply(key, to: text)
        } label: {
            label(for: key)
                .font(.title2)
                .frame(maxWidth: .infinity, minHeight: max(60, keyHeight))
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("Tender.key.\(key.identifier)")
    }

    @ViewBuilder
    private func label(for key: KeypadKey) -> some View {
        switch key {
        case .digit, .tripleZero:
            Text(key.identifier)
        case .delete:
            Label("Hapus angka", systemImage: "delete.left")
                .labelStyle(.iconOnly)
        }
    }
}
