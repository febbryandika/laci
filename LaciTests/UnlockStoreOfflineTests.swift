import Foundation
@testable import Laci
import Testing

/// Needs no StoreKit test session, unlike `UnlockStoreTests`: the offline store never asks the App Store.
@MainActor
@Suite("Unlock store offline")
struct UnlockStoreOfflineTests {
    @Test("An offline store reports the price as unloadable without a network round trip")
    func priceFails() async {
        let store = UnlockStore(simulatesOffline: true)
        await store.loadProduct()
        #expect(store.productLoadFailed)
        #expect(store.product == nil)
        #expect(!store.isUnlocked)
    }
}
