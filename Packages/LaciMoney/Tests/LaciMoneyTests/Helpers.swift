import Foundation
import Testing

/// `Decimal` float literals are not exact (`1.11` is 1.1100000000000002048), so every non-integer
/// value in these tests is built from a string.
func dec(_ text: String) throws -> Decimal {
    try #require(Decimal(string: text))
}
