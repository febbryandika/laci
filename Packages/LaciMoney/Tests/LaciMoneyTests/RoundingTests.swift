import Foundation
import LaciMoney
import Testing

@Suite("Rounding")
struct RoundingTests {
    @Test("Banker's rounding sends ties to the even neighbour", arguments: [
        ("1.125", "1.12"), ("1.135", "1.14"), ("-1.125", "-1.12"), ("-1.135", "-1.14"), ("1.126", "1.13"),
    ])
    func bankersTies(input: String, expected: String) throws {
        #expect(try Rounding.bankers(dec(input), scale: 2) == dec(expected))
    }

    @Test("Banker's rounding at scale 0")
    func bankersScaleZero() throws {
        #expect(try Rounding.bankers(dec("2.5"), scale: 0) == 2)
        #expect(try Rounding.bankers(dec("3.5"), scale: 0) == 4)
    }

    @Test("toNearest 100 rounds half away from zero, not to even", arguments: [
        (12350, 12400), (12349, 12300), (12450, 12500), (12250, 12300),
        (50, 100), (-50, -100), (0, 0), (12300, 12300),
    ])
    func toNearestHundred(input: Int, expected: Int) {
        #expect(Rounding.toNearest(Decimal(input), increment: 100) == Decimal(expected))
    }

    @Test("toNearest takes any increment")
    func toNearestThousand() {
        #expect(Rounding.toNearest(12500, increment: 1000) == 13000)
        #expect(Rounding.toNearest(12499, increment: 1000) == 12000)
    }
}
