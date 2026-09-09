import LaciMoney
import Testing

@Suite("Close-out")
struct CloseOutTests {
    /// expected = 200 000 + 1 234 500 − 34 500 − 150 000 = 1 250 000
    let inputs = DrawerInputs(
        openingFloat: Money(200_000),
        cashSales: Money(1_234_500),
        cashRefunds: Money(34500),
        payouts: Money(150_000)
    )

    @Test("expected = openingFloat + cashSales − cashRefunds − payouts")
    func expected() {
        #expect(CloseOutEngine.reconcile(inputs, counted: Money(1_250_000)).expected == Money(1_250_000))
    }

    @Test("A perfect count has zero discrepancy and is not short")
    func exactCount() {
        let result = CloseOutEngine.reconcile(inputs, counted: Money(1_250_000))
        #expect(result == DrawerResult(expected: Money(1_250_000), counted: Money(1_250_000), discrepancy: .zero))
        #expect(!result.isShort)
    }

    @Test("Counting less than expected is short with a negative discrepancy")
    func short() {
        let result = CloseOutEngine.reconcile(inputs, counted: Money(1_249_800))
        #expect(result.discrepancy == Money(-200))
        #expect(result.isShort)
    }

    @Test("Counting more than expected is over, not short")
    func over() {
        let result = CloseOutEngine.reconcile(inputs, counted: Money(1_250_500))
        #expect(result.discrepancy == Money(500))
        #expect(!result.isShort)
    }
}
