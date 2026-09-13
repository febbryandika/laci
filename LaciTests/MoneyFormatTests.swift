import Foundation
@testable import Laci
import Testing

@MainActor
@Suite("Money format")
struct MoneyFormatTests {
    @Test("On screen: the Rp prefix with Indonesian grouping")
    func printed() {
        let text = Decimal(15000).formatted(MoneyFormat.rupiah)
        #expect(text.hasPrefix("Rp"))
        #expect(text.contains("15.000"))
    }

    @Test("Spoken: the currency by name, never the Rp abbreviation")
    func spoken() {
        let text = Decimal(15000).formatted(MoneyFormat.spoken)
        #expect(text.contains("15.000"))
        #expect(text.localizedCaseInsensitiveContains("rupiah"))
        #expect(!text.contains("Rp "))
    }

    @Test("Fractions print only when present", arguments: [("2500", "2.500"), ("2500.5", "2.500,5")])
    func fractions(raw: String, expected: String) throws {
        let amount = try #require(Decimal(string: raw))
        #expect(amount.formatted(MoneyFormat.rupiah).contains(expected))
    }
}
