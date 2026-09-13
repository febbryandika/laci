import Foundation
@testable import Laci
import StoreKit
import StoreKitTest
import Testing

/// The configuration the Xcode scheme uses too; one file, two readers.
private nonisolated let configurationURL = URL(filePath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "Config/Laci.storekit")

/// On the iOS 26.3–26.5 simulator runtimes the local test store only accepts a session started
/// from the Xcode IDE; under `xcodebuild` every call fails with SKInternalErrorDomain 3. The suite
/// skips itself on that signal rather than fail on a store it cannot reach.
private nonisolated func testStoreReachable() -> Bool {
    guard let probe = try? SKTestSession(contentsOf: configurationURL) else { return false }
    return !probe.storefront.isEmpty
}

/// SPEC §16.9: purchase, revocation and restore against StoreKit's local test store. Serialized,
/// because the test store is process-wide.
@MainActor
@Suite(
    "Unlock store (StoreKit test session)", .serialized,
    .enabled(if: testStoreReachable(), "StoreKit test store is only reachable from the Xcode IDE on this runtime")
)
struct UnlockStoreTests {
    let session: SKTestSession

    init() throws {
        session = try SKTestSession(contentsOf: configurationURL)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
    }

    @Test("A purchase unlocks, and the price comes from the configuration")
    func purchaseUnlocks() async throws {
        let store = UnlockStore()
        store.start()
        await store.loadProduct()
        let product = try #require(store.product)
        #expect(product.id == UnlockStore.productID)
        #expect(!product.displayPrice.isEmpty)
        #expect(store.isUnlocked == false)

        try await store.purchase(product)
        #expect(store.isUnlocked)
    }

    @Test("A refund revokes the entitlement through the updates listener")
    func refundRevokes() async throws {
        let store = UnlockStore()
        store.start()
        await store.loadProduct()
        let product = try #require(store.product)
        try await store.purchase(product)
        #expect(store.isUnlocked)

        let transaction = try #require(session.allTransactions().first)
        try session.refundTransaction(identifier: transaction.identifier)
        let revoked = await until(.seconds(10)) { !store.isUnlocked }
        #expect(revoked)
    }

    @Test("An entitlement bought outside the app is found by refresh and by restore")
    func restoreFindsExistingPurchase() async throws {
        _ = try await session.buyProduct(identifier: UnlockStore.productID)
        let store = UnlockStore()
        await store.refresh()
        #expect(store.isUnlocked)

        let fresh = UnlockStore()
        try await fresh.restore()
        #expect(fresh.isUnlocked)
    }
}
