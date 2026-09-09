import Foundation
import LaciMoney
import Testing

@Suite("Money")
struct MoneyTests {
    @Test("Arithmetic and comparison go through Decimal")
    func arithmetic() {
        let price = Money(2499)
        #expect(price + Money(1) == Money(2500))
        #expect(price - Money(2499) == .zero)
        #expect(price.times(3) == Money(7497))
        #expect(Money(1) < Money(2))
        #expect(Money(2) >= Money(2))
        #expect([Money(1), Money(2), Money(3)].reduce(.zero, +) == Money(6))
    }

    @Test("Equal amounts at different scales are equal and hash alike")
    func equalityAcrossScale() throws {
        let whole = Money(12400)
        let scaled = try money("12400.00")
        #expect(whole == scaled)
        #expect(whole.hashValue == scaled.hashValue)
    }
}

@Suite("Discount")
struct DiscountTests {
    let gross = Money(12345)

    @Test("none takes nothing")
    func nothing() {
        #expect(Discount.none.applied(to: gross) == .zero)
    }

    @Test("An amount below the gross is taken as given")
    func amount() {
        #expect(Discount.amount(Money(1500)).applied(to: gross) == Money(1500))
    }

    @Test("An amount above the gross is clamped to the gross")
    func amountClamped() {
        #expect(Discount.amount(Money(20000)).applied(to: gross) == gross)
    }

    @Test("Percent is banker's-rounded to two places")
    func percent() throws {
        #expect(try Discount.percent(15).applied(to: gross) == money("1851.75"))
        #expect(try Discount.percent(dec("12.5")).applied(to: gross) == money("1543.12"))
        #expect(try Discount.percent(50).applied(to: Money(999)) == money("499.5"))
    }

    @Test("Percent is clamped to 0...100")
    func percentClamped() {
        #expect(Discount.percent(150).applied(to: gross) == gross)
        #expect(Discount.percent(100).applied(to: gross) == gross)
        #expect(Discount.percent(-10).applied(to: gross) == .zero)
        #expect(Discount.percent(0).applied(to: gross) == .zero)
    }
}
