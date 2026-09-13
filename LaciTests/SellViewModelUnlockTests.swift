import Foundation
@testable import Laci
import LaciCore
import LaciMoney
import Testing

private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

/// SPEC §3.4 at the checkout button: the limit is two here so no test rings thirty sales.
@MainActor
@Suite("Checkout unlock gate")
struct SellViewModelUnlockTests {
    let dependencies: Dependencies
    let unlock = FakeUnlockStore(isUnlocked: false)
    let viewModel: SellViewModel

    init() throws {
        dependencies = try Dependencies.inMemory()
        viewModel = SellViewModel(dependencies: dependencies, unlock: unlock, trialLimit: 2, now: { fixedNow })
        let product = Product(
            sku: "A", name: "Item A", unit: "pcs", cost: 0, price: 12350, tracksStock: false, stockOnHand: 0,
            updatedAt: fixedNow
        )
        try dependencies.products.create(product)
        viewModel.loadCatalogue()
    }

    /// One line of A, paid exactly; returns the sale number or nil when the checkout was refused.
    @discardableResult
    func ringUpCash() -> Int? {
        viewModel.query = "A"
        viewModel.addFirstResult()
        let before = viewModel.lastSale?.number
        viewModel.checkoutCash(tendered: viewModel.cashTotal)
        let after = viewModel.lastSale?.number
        return after == before ? nil : after
    }

    @Test("Under the limit a locked shop still sells")
    func underTheLimitSells() {
        #expect(viewModel.isCheckoutLocked() == false)
        #expect(ringUpCash() == 1)
        #expect(viewModel.tenderError == nil)
        #expect(viewModel.isCheckoutLocked() == false)
    }

    @Test("At the limit cash checkout is refused with .locked and nothing reaches the store")
    func atTheLimitCashIsRefused() throws {
        ringUpCash()
        ringUpCash()
        #expect(viewModel.isCheckoutLocked())

        #expect(ringUpCash() == nil)
        #expect(viewModel.tenderError == .locked)
        #expect(viewModel.lines.count == 1)
        #expect(try dependencies.sales.nextNumber() == 3)
    }

    @Test("At the limit non-cash checkout is refused the same way", arguments: NonCashMethod.allCases)
    func atTheLimitNonCashIsRefused(method: NonCashMethod) throws {
        ringUpCash()
        ringUpCash()
        viewModel.query = "A"
        viewModel.addFirstResult()

        viewModel.checkoutNonCash(method, reference: "REF-1")
        #expect(viewModel.tenderError == .locked)
        #expect(viewModel.lines.count == 1)
        #expect(try dependencies.sales.nextNumber() == 3)
    }

    @Test("Unlocking bypasses the limit")
    func unlockedBypassesTheLimit() {
        unlock.isUnlocked = true
        #expect(ringUpCash() == 1)
        #expect(ringUpCash() == 2)
        #expect(ringUpCash() == 3)
        #expect(viewModel.tenderError == nil)
    }

    @Test("Voiding a sale frees a slot")
    func voidFreesASlot() throws {
        let first = try #require(ringUpCash())
        ringUpCash()
        #expect(viewModel.isCheckoutLocked())

        let found = try dependencies.sales.sale(number: first)
        let sale = try #require(found)
        try dependencies.sales.void(saleID: sale.id, reason: "salah", occurredAt: fixedNow)
        #expect(viewModel.isCheckoutLocked() == false)
        #expect(ringUpCash() == 3)
    }

    @Test("The lock is decided per attempt, so an unlock mid-session clears a .locked retry")
    func unlockMidSessionClearsTheError() {
        ringUpCash()
        ringUpCash()
        #expect(ringUpCash() == nil)
        #expect(viewModel.tenderError == .locked)

        unlock.isUnlocked = true
        viewModel.checkoutCash(tendered: viewModel.cashTotal)
        #expect(viewModel.tenderError == nil)
        #expect(viewModel.lastSale?.number == 3)
    }
}
