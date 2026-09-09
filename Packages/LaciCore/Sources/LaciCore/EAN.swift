import Foundation

/// Mod-10 validation for EAN-13 and EAN-8 (SPEC §6). A failing checksum means "scan again"; it must
/// never be reported as an unknown product, because a misread and a missing SKU are different problems.
public enum EAN {
    public enum Validation: Hashable, Sendable {
        case valid(Symbology)
        case badChecksum
        case notEAN
    }

    public static func validate(_ payload: String) -> Validation {
        let digits = payload.compactMap(\.asciiDigit)
        guard digits.count == payload.count else { return .notEAN }
        let symbology: Symbology
        switch digits.count {
        case 13: symbology = .ean13
        case 8: symbology = .ean8
        default: return .notEAN
        }
        let body = digits.dropLast()
        return checkDigit(for: body) == digits[digits.count - 1] ? .valid(symbology) : .badChecksum
    }

    /// Weights 3,1,3,… from the rightmost body digit; the check digit brings the sum to a multiple of ten.
    private static func checkDigit(for body: some Collection<Int>) -> Int {
        let sum = body.reversed().enumerated().reduce(0) { total, pair in
            total + pair.element * (pair.offset.isMultiple(of: 2) ? 3 : 1)
        }
        return (10 - sum % 10) % 10
    }
}

private extension Character {
    /// ASCII digits only: a fullwidth "７" is not something a barcode carries.
    var asciiDigit: Int? {
        guard isASCII, let value = wholeNumberValue else { return nil }
        return value
    }
}
