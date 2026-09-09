import Foundation
import LaciMoney
import Testing

@Suite("Cash rounding")
struct RoundForCashTests {
    @Test("Rounds to the nearest Rp 100, half away from zero", arguments: [
        (12350, 12400), (12349, 12300), (12450, 12500), (12250, 12300), (12300, 12300),
    ])
    func roundForCash(total: Int, expected: Int) {
        #expect(Tender.roundForCash(Money(Decimal(total))) == Money(Decimal(expected)))
    }
}

@Suite("Settlement")
struct SettleTests {
    @Test("Exact rounded tender: change zero, delta is the rounding")
    func exactTender() throws {
        let settlement = try #require(Tender.settle(total: Money(12350), tendered: Money(12400)))
        #expect(settlement == CashSettlement(
            exact: Money(12350), rounded: Money(12400), roundingDelta: Money(50),
            tendered: Money(12400), change: .zero
        ))
    }

    @Test("Change is tendered minus the rounded total")
    func change() throws {
        let settlement = try #require(Tender.settle(total: Money(12350), tendered: Money(20000)))
        #expect(settlement.change == Money(7600))
    }

    @Test("Rounding down: negative delta, change against the rounded figure")
    func roundedDown() throws {
        let down = try #require(Tender.settle(total: Money(12349), tendered: Money(12300)))
        #expect(down.roundingDelta == Money(-49))
        #expect(down.change == .zero)
        let overpaid = try #require(Tender.settle(total: Money(12349), tendered: Money(12349)))
        #expect(overpaid.change == Money(49))
    }

    @Test("Short tender is nil, never negative change", arguments: [(12350, 12399), (12350, 12350), (12350, 0)])
    func short(total: Int, tendered: Int) {
        #expect(Tender.settle(total: Money(Decimal(total)), tendered: Money(Decimal(tendered))) == nil)
    }
}

@Suite("Quick tender")
struct SuggestionTests {
    @Test("Rounded total, then the four smallest note multiples above it", arguments: [
        (12350, [12400, 13000, 14000, 15000, 20000]),
        (100_000, [100_000, 101_000, 102_000, 105_000, 110_000]),
        (99950, [100_000, 101_000, 102_000, 105_000, 110_000]),
        (999, [1000, 2000, 5000, 10000, 20000]),
        (0, [0, 1000, 2000, 5000, 10000]),
        (250_000, [250_000, 251_000, 252_000, 255_000, 260_000]),
    ])
    func suggestions(total: Int, expected: [Int]) {
        #expect(Tender.suggestions(for: Money(Decimal(total))) == expected.map { Money(Decimal($0)) })
    }

    @Test("Always five, strictly increasing, starting at the rounded total")
    func shape() {
        let total = Money(37421)
        let suggestions = Tender.suggestions(for: total)
        #expect(suggestions.count == 5)
        #expect(suggestions.first == Tender.roundForCash(total))
        #expect(zip(suggestions, suggestions.dropFirst()).allSatisfy { $0 < $1 })
    }
}
