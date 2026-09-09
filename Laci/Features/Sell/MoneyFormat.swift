import Foundation

/// Money is rendered through a `FormatStyle`, never a hand-built string, so VoiceOver announces an
/// amount and the receipt path in a later phase can reuse the same style (SPEC §9).
enum MoneyFormat {
    static let rupiah = Decimal.FormatStyle.Currency(code: "IDR", locale: ShopDefaults.locale)
        .precision(.fractionLength(0 ... 2))

    /// Plain digits for read-back into text fields; no grouping, so "12400" is what the cashier typed.
    static let plain = Decimal.FormatStyle.number.locale(ShopDefaults.locale).grouping(.never)
}

/// Typed amounts and quantities. Digits with at most one decimal separator; anything else is nil.
/// `Decimal(string:)` accepts a numeric prefix ("12abc" → 12), so the shape is checked first.
enum DecimalInput {
    static func parse(_ text: String) -> Decimal? {
        let normalised = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !normalised.isEmpty,
              normalised.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              normalised.filter({ $0 == "." }).count <= 1,
              normalised.first?.isNumber == true
        else { return nil }
        return Decimal(string: normalised, locale: Locale(identifier: "en_US_POSIX"))
    }
}
